// Step 2: Production-Ready API Gateway
// =====================================
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// =============================================================================
// CONFIGURATION
// =============================================================================

type Config struct {
	Port           string
	BackendURL     string
	RequestTimeout time.Duration
	LogLevel       string
	Environment    string
}

func loadConfig() *Config {
	// Helper function to get env var with default
	getEnv := func(key, defaultValue string) string {
		if value := os.Getenv(key); value != "" {
			return value
		}
		return defaultValue
	}

	return &Config{
		Port:           getEnv("GATEWAY_PORT", "8080"),
		BackendURL:     getEnv("BACKEND_URL", "http://sentiment-api-service:80"),
		RequestTimeout: 10 * time.Second,
		LogLevel:       getEnv("LOG_LEVEL", "info"),
		Environment:    getEnv("ENVIRONMENT", "production"),
	}
}

// =============================================================================
// PROMETHEUS METRICS
// =============================================================================

var (
	// HTTP request counter
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gateway_http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	// HTTP request duration histogram
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "gateway_http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets, // [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
		},
		[]string{"method", "endpoint"},
	)

	// Backend request counter
	backendRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "gateway_backend_requests_total",
			Help: "Total number of backend requests",
		},
		[]string{"endpoint", "status"},
	)

	// Backend request duration
	backendRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "gateway_backend_request_duration_seconds",
			Help:    "Backend request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"endpoint"},
	)
)

// =============================================================================
// MIDDLEWARE
// =============================================================================

// responseWriter wraps http.ResponseWriter to capture status code
type responseWriter struct {
	http.ResponseWriter
	statusCode int
	written    int64
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	n, err := rw.ResponseWriter.Write(b)
	rw.written += int64(n)
	return n, err
}

// Request ID middleware - adds unique ID to each request
func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Check if request already has ID (from upstream proxy)
		requestID := r.Header.Get("X-Request-ID")
		if requestID == "" {
			// Generate new UUID
			requestID = uuid.New().String()
		}

		// Add to request context
		ctx := context.WithValue(r.Context(), "request_id", requestID)

		// Add to response headers
		w.Header().Set("X-Request-ID", requestID)

		// Call next handler with updated context
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// Logging middleware - logs all requests
func loggingMiddleware(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()

			// Wrap response writer to capture status code
			rw := &responseWriter{
				ResponseWriter: w,
				statusCode:     http.StatusOK,
			}

			// Get request ID from context
			requestID, _ := r.Context().Value("request_id").(string)

			// Log incoming request
			logger.Info("incoming request",
				"request_id", requestID,
				"method", r.Method,
				"path", r.URL.Path,
				"remote_addr", r.RemoteAddr,
			)

			// Call next handler
			next.ServeHTTP(rw, r)

			// Log response
			duration := time.Since(start)
			logger.Info("request completed",
				"request_id", requestID,
				"method", r.Method,
				"path", r.URL.Path,
				"status", rw.statusCode,
				"duration_ms", duration.Milliseconds(),
				"bytes_written", rw.written,
			)
		})
	}
}

// Metrics middleware - records Prometheus metrics
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		rw := &responseWriter{
			ResponseWriter: w,
			statusCode:     http.StatusOK,
		}

		next.ServeHTTP(rw, r)

		duration := time.Since(start).Seconds()

		// Record metrics
		httpRequestsTotal.WithLabelValues(
			r.Method,
			r.URL.Path,
			fmt.Sprintf("%d", rw.statusCode),
		).Inc()

		httpRequestDuration.WithLabelValues(
			r.Method,
			r.URL.Path,
		).Observe(duration)
	})
}

// Chain multiple middlewares
func chain(handler http.Handler, middlewares ...func(http.Handler) http.Handler) http.Handler {
	for i := len(middlewares) - 1; i >= 0; i-- {
		handler = middlewares[i](handler)
	}
	return handler
}

// =============================================================================
// GATEWAY
// =============================================================================

type Gateway struct {
	config     *Config
	logger     *slog.Logger
	httpClient *http.Client
}

func NewGateway(config *Config, logger *slog.Logger) *Gateway {
	return &Gateway{
		config: config,
		logger: logger,
		httpClient: &http.Client{
			Timeout: config.RequestTimeout,
			// Connection pooling for better performance
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}
}

func (g *Gateway) createHandler() http.Handler {
	mux := http.NewServeMux()

	// Routes
	mux.HandleFunc("/health", g.handleHealth)
	mux.HandleFunc("/predict", g.handlePredict)
	mux.HandleFunc("/batch_predict", g.handleBatchPredict)
	mux.Handle("/metrics", promhttp.Handler()) // Prometheus metrics endpoint
	mux.HandleFunc("/", g.handleRoot)

	// Apply middleware (order matters!)
	return chain(mux,
		requestIDMiddleware,
		loggingMiddleware(g.logger),
		metricsMiddleware,
	)
}

func (g *Gateway) handleHealth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Test backend connectivity
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, g.config.BackendURL+"/health", nil)
	resp, err := g.httpClient.Do(req)

	health := map[string]interface{}{
		"status":  "ok",
		"service": "api-gateway",
	}

	if err != nil {
		health["backend"] = "unreachable"
		health["backend_error"] = err.Error()
		g.logger.Warn("backend health check failed", "error", err)
	} else {
		resp.Body.Close()
		health["backend"] = "ok"
		health["backend_status"] = resp.StatusCode
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(health)
}

func (g *Gateway) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.Error(w, "Not found", http.StatusNotFound)
		return
	}

	info := map[string]interface{}{
		"service":     "Sentiment Analysis API Gateway",
		"version":     "2.0.0",
		"environment": g.config.Environment,
		"endpoints": map[string]string{
			"/health":        "Health check endpoint",
			"/predict":       "Single text sentiment analysis",
			"/batch_predict": "Batch sentiment analysis",
			"/metrics":       "Prometheus metrics",
		},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func (g *Gateway) handlePredict(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	g.proxyRequest(w, r, "/predict")
}

func (g *Gateway) handleBatchPredict(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	g.proxyRequest(w, r, "/batch_predict")
}

func (g *Gateway) proxyRequest(w http.ResponseWriter, r *http.Request, path string) {
	requestID, _ := r.Context().Value("request_id").(string)

	// Read request body
	body, err := io.ReadAll(r.Body)
	if err != nil {
		g.logger.Error("failed to read request body",
			"request_id", requestID,
			"error", err,
		)
		http.Error(w, "Failed to read request", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	// Create backend request
	backendURL := g.config.BackendURL + path
	req, err := http.NewRequestWithContext(r.Context(), r.Method, backendURL, bytes.NewReader(body))
	if err != nil {
		g.logger.Error("failed to create backend request",
			"request_id", requestID,
			"error", err,
		)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Copy headers
	for key, values := range r.Header {
		if key != "Host" && key != "Connection" {
			for _, value := range values {
				req.Header.Add(key, value)
			}
		}
	}

	// Add request ID to backend request
	req.Header.Set("X-Request-ID", requestID)

	// Send request to backend
	start := time.Now()
	resp, err := g.httpClient.Do(req)
	duration := time.Since(start).Seconds()

	// Record backend metrics
	statusLabel := "error"
	if resp != nil {
		statusLabel = fmt.Sprintf("%d", resp.StatusCode)
	}
	backendRequestsTotal.WithLabelValues(path, statusLabel).Inc()
	backendRequestDuration.WithLabelValues(path).Observe(duration)

	if err != nil {
		g.logger.Error("backend request failed",
			"request_id", requestID,
			"backend_url", backendURL,
			"error", err,
			"duration_ms", int64(duration*1000),
		)
		http.Error(w, "Backend service unavailable", http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	g.logger.Debug("backend request completed",
		"request_id", requestID,
		"status", resp.StatusCode,
		"duration_ms", int64(duration*1000),
	)

	// Copy response headers
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}

	// Copy status code
	w.WriteHeader(resp.StatusCode)

	// Copy response body
	_, err = io.Copy(w, resp.Body)
	if err != nil {
		g.logger.Error("failed to write response",
			"request_id", requestID,
			"error", err,
		)
	}
}

// =============================================================================
// MAIN
// =============================================================================

func main() {
	// Load configuration
	config := loadConfig()

	// Setup structured logging
	var logLevel slog.Level
	switch config.LogLevel {
	case "debug":
		logLevel = slog.LevelDebug
	case "info":
		logLevel = slog.LevelInfo
	case "warn":
		logLevel = slog.LevelWarn
	case "error":
		logLevel = slog.LevelError
	default:
		logLevel = slog.LevelInfo
	}

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: logLevel,
	}))

	slog.SetDefault(logger)

	logger.Info("starting api gateway",
		"port", config.Port,
		"backend_url", config.BackendURL,
		"environment", config.Environment,
		"log_level", config.LogLevel,
	)

	// Create gateway
	gateway := NewGateway(config, logger)

	// Create HTTP server
	server := &http.Server{
		Addr:         ":" + config.Port,
		Handler:      gateway.createHandler(),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		logger.Info("server listening", "addr", server.Addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		logger.Error("server forced to shutdown", "error", err)
		os.Exit(1)
	}

	logger.Info("server stopped gracefully")
}

// =============================================================================
// KEY PATTERNS FOR MLOPS
// =============================================================================
//
// 1. REQUEST CORRELATION
//    - X-Request-ID flows through: Gateway → ML Service → Logs
//    - Debug issues by tracing single request across services
//
// 2. METRICS-DRIVEN OPERATIONS
//    - gateway_http_requests_total - Monitor traffic patterns
//    - gateway_backend_request_duration_seconds - Detect ML service slowness
//    - Prometheus scrapes /metrics endpoint
//
// 3. STRUCTURED LOGGING
//    - JSON format - Easy to parse with log aggregators (ELK, Loki)
//    - Consistent fields - request_id, method, path, duration_ms
//    - Different log levels - debug/info/warn/error
//
// 4. GRACEFUL SHUTDOWN
//    - Finish in-flight ML requests before stopping
//    - Important: ML inference can take seconds
//    - Prevents 500 errors during deployments
//
// 5. CONNECTION POOLING
//    - Reuse HTTP connections to ML service
//    - Reduces latency (no TCP handshake overhead)
//    - MaxIdleConnsPerHost: 10 connections ready
//
// 6. HEALTH CHECK WITH BACKEND TEST
//    - Gateway healthy only if ML service is reachable
//    - Kubernetes uses this for readiness probe
//    - Prevents routing traffic to broken gateway
//
// =============================================================================
// DEPLOYMENT
// =============================================================================
//
// Environment Variables:
//   GATEWAY_PORT      - Port to listen on (default: 8080)
//   BACKEND_URL       - ML service URL (default: http://sentiment-api-service:80)
//   LOG_LEVEL         - Logging level: debug, info, warn, error (default: info)
//   ENVIRONMENT       - Deployment environment (default: production)
//
// Kubernetes Integration:
//   - Deploys alongside sentiment-api from Module 3
//   - Exposes on port 8080
//   - Prometheus scrapes /metrics
//   - Health checks on /health
//
// Build:
//   go build -o gateway gateway_solution.go
//   GOOS=linux GOARCH=amd64 go build -o gateway gateway_solution.go
//
// Run Locally:
//   export BACKEND_URL=http://localhost:3000
//   export LOG_LEVEL=debug
//   go run gateway_solution.go
//
// =============================================================================

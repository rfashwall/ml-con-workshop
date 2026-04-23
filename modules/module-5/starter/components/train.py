"""
Exercise 2: Training Component for Kubeflow Pipeline
=====================================================

What you'll learn:
- Input/Output Model artifacts
- Metrics logging in Kubeflow
- Collaborative filtering with SVD
- Model serialization with pickle

Instructions:
Fill in the 10 TODOs marked with '????' or '# YOUR CODE HERE'
Each TODO has inline hints showing exactly what to use.
"""

from kfp.dsl import component, Input, Output, Dataset, Model, Metrics


# TODO 1: Complete the @component decorator
# HINT: base_image="python:3.11-slim"
# HINT: packages_to_install=["pandas==2.0.3", "numpy==1.24.3", "scikit-learn==1.3.2"]
@component(
    base_image="????",  # TODO 1: Set to "python:3.11-slim"
    packages_to_install=["????", "????", "????"]  # TODO 1: Set to ["pandas==2.0.3", "numpy==1.24.3", "scikit-learn==1.3.2"]
)
def train_model(
    train_data: Input[Dataset],
    model: Output[Model],
    metrics: Output[Metrics],
    n_components: int = 20,
    random_state: int = 42
):
    """
    Train recommendation model using collaborative filtering

    Args:
        train_data: Input training dataset
        model: Output trained model
        metrics: Output training metrics
        n_components: Number of latent factors for SVD
        random_state: Random seed
    """
    import pandas as pd
    import numpy as np
    import pickle
    from sklearn.decomposition import TruncatedSVD
    from sklearn.metrics import mean_squared_error
    import logging

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # TODO 2: Load training data — pd.read_csv(train_data.path)
    ratings_df = None  # YOUR CODE HERE

    logger.info(f"Training on {len(ratings_df)} ratings")

    # Create encoders for user and movie IDs
    unique_users = ratings_df['userId'].unique()
    unique_movies = ratings_df['movieId'].unique()

    user_encoder = {user_id: idx for idx, user_id in enumerate(unique_users)}
    movie_encoder = {movie_id: idx for idx, movie_id in enumerate(unique_movies)}

    logger.info(f"Encoded {len(unique_users)} users and {len(unique_movies)} movies")

    # Create user-movie matrix
    n_users = len(user_encoder)
    n_movies = len(movie_encoder)
    user_movie_matrix = np.zeros((n_users, n_movies))

    for _, row in ratings_df.iterrows():
        user_idx = user_encoder[row['userId']]
        movie_idx = movie_encoder[row['movieId']]
        user_movie_matrix[user_idx, movie_idx] = row['rating']

    logger.info(f"Created user-movie matrix: {user_movie_matrix.shape}")

    # TODO 3: Create TruncatedSVD(n_components=n_components, random_state=random_state)
    svd_model = None  # YOUR CODE HERE

    # TODO 4: Fit and transform the user_movie_matrix — svd_model.fit_transform(user_movie_matrix)
    #         The result is the user_factors matrix
    user_factors = None  # YOUR CODE HERE

    # TODO 5: Get movie factors from svd_model.components_.T
    movie_factors = None  # YOUR CODE HERE

    # Calculate training metrics
    predicted_ratings = user_factors @ movie_factors.T

    # RMSE on observed ratings
    observed_mask = user_movie_matrix > 0
    observed_ratings = user_movie_matrix[observed_mask]
    predicted_observed = predicted_ratings[observed_mask]

    rmse = np.sqrt(mean_squared_error(observed_ratings, predicted_observed))
    explained_variance = svd_model.explained_variance_ratio_.sum()

    logger.info(f"Training complete. RMSE: {rmse:.3f}, "
               f"Explained Variance: {explained_variance:.3f}")

    # TODO 6: Log RMSE — metrics.log_metric("rmse", float(rmse))
    # YOUR CODE HERE

    # TODO 7: Log explained variance — metrics.log_metric("explained_variance", float(explained_variance))
    # YOUR CODE HERE

    # TODO 8: Log additional metrics: "n_components", "n_users", "n_movies", "n_ratings"
    #         Use metrics.log_metric(name, value) for each
    # YOUR CODE HERE (4 lines)

    # Save model data
    model_data = {
        'user_factors': user_factors,
        'movie_factors': movie_factors,
        'user_encoder': user_encoder,
        'movie_encoder': movie_encoder,
        'user_decoder': {idx: user_id for user_id, idx in user_encoder.items()},
        'movie_decoder': {idx: movie_id for movie_id, idx in movie_encoder.items()},
        'user_movie_matrix': user_movie_matrix,
        'n_components': n_components,
        'random_state': random_state
    }

    # TODO 9: Save model_data dict to model.path using pickle
    #         with open(model.path, 'wb') as f: pickle.dump(model_data, f)
    # YOUR CODE HERE (2 lines)

    logger.info(f"Model saved to {model.path}")


# =============================================================================
# KEY CONCEPTS
# =============================================================================
#
# 1. COLLABORATIVE FILTERING
#    - Uses user-item interaction matrix (users × movies × ratings)
#    - Factorizes matrix into user factors and movie factors
#    - Predicts ratings as: predicted_rating = user_factor @ movie_factor
#
# 2. TRUNCATED SVD (Singular Value Decomposition)
#    - Reduces high-dimensional user-movie matrix to lower dimensions
#    - n_components: Number of latent factors (e.g., 20)
#    - Captures patterns like "action movie lovers" or "comedy fans"
#    - fit_transform() returns user factors
#    - components_.T returns movie factors
#
# 3. KUBEFLOW METRICS
#    - metrics.log_metric(name, value) logs metrics to Kubeflow UI
#    - Visible in pipeline run dashboard
#    - Helps compare different model configurations
#
# 4. MODEL ARTIFACTS
#    - Output[Model]: Declares model as pipeline artifact
#    - Saved to model.path (Kubeflow-managed storage)
#    - Can be loaded by downstream components (evaluation, deployment)
#
# 5. ENCODERS
#    - Convert user/movie IDs to matrix indices
#    - user_encoder: {user_id: matrix_index}
#    - decoder: {matrix_index: user_id}
#    - Needed for prediction: Look up user/movie, get indices, compute dot product
#
"""
Exercise 2 (continued): Evaluation Component for Kubeflow Pipeline
===================================================================

What you'll learn:
- Loading Model artifacts from previous steps
- Evaluation metrics (RMSE, MAE, coverage)
- Returning values from components
- Handling cold-start problem
"""

from kfp.dsl import component, Input, Output, Dataset, Model, Metrics


# TODO 1: Complete the @component decorator
# HINT: base_image="python:3.11-slim"
# HINT: packages_to_install=["pandas==2.0.3", "numpy==1.24.3", "scikit-learn==1.3.2"]
@component(
    base_image="????",  # TODO 1: Set to "python:3.11-slim"
    packages_to_install=["????", "????", "????"]  # TODO 1: Set to ["pandas==2.0.3", "numpy==1.24.3", "scikit-learn==1.3.2"]
)
def evaluate_model(
    test_data: Input[Dataset],
    model: Input[Model],
    metrics: Output[Metrics]
) -> str:
    """
    Evaluate recommendation model on test data

    Args:
        test_data: Input test dataset
        model: Input trained model
        metrics: Output evaluation metrics

    Returns:
        Evaluation status message
    """
    import pandas as pd
    import numpy as np
    import pickle
    from sklearn.metrics import mean_squared_error, mean_absolute_error
    import logging

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # TODO 2: Load model from model.path using pickle
    #         with open(model.path, 'rb') as f: model_data = pickle.load(f)
    # YOUR CODE HERE (2 lines)

    user_factors = model_data['user_factors']
    movie_factors = model_data['movie_factors']
    user_encoder = model_data['user_encoder']
    movie_encoder = model_data['movie_encoder']

    # TODO 3: Load test data — pd.read_csv(test_data.path)
    test_df = None  # YOUR CODE HERE

    logger.info(f"Evaluating on {len(test_df)} ratings")

    # Make predictions on test set
    predictions = []
    actuals = []

    for _, row in test_df.iterrows():
        user_id = row['userId']
        movie_id = row['movieId']
        actual_rating = row['rating']

        # Skip if user or movie not in training set (cold-start problem)
        if user_id not in user_encoder or movie_id not in movie_encoder:
            continue

        user_idx = user_encoder[user_id]
        movie_idx = movie_encoder[movie_id]

        # Predict rating
        predicted_rating = user_factors[user_idx] @ movie_factors[movie_idx]
        predicted_rating = np.clip(predicted_rating, 1.0, 5.0)

        predictions.append(predicted_rating)
        actuals.append(actual_rating)

    predictions = np.array(predictions)
    actuals = np.array(actuals)

    # Calculate metrics
    rmse = np.sqrt(mean_squared_error(actuals, predictions))
    mae = mean_absolute_error(actuals, predictions)

    # Calculate coverage (how many test users/movies were in training set)
    test_users = test_df['userId'].unique()
    test_movies = test_df['movieId'].unique()
    user_coverage = len(set(test_users) & set(user_encoder.keys())) / len(test_users)
    movie_coverage = len(set(test_movies) & set(movie_encoder.keys())) / len(test_movies)

    logger.info(f"Test RMSE: {rmse:.3f}")
    logger.info(f"Test MAE: {mae:.3f}")
    logger.info(f"User coverage: {user_coverage:.2%}")
    logger.info(f"Movie coverage: {movie_coverage:.2%}")

    # TODO 4: Log test RMSE — metrics.log_metric("test_rmse", float(rmse))
    # YOUR CODE HERE

    # TODO 5: Log test MAE — metrics.log_metric("test_mae", float(mae))
    # YOUR CODE HERE

    # TODO 6: Log coverage metrics: "user_coverage", "movie_coverage", "n_test_ratings", "n_evaluated_ratings"
    #         Use metrics.log_metric(name, value) for each
    # YOUR CODE HERE (4 lines)

    # Return evaluation status
    status = f"Evaluation complete: RMSE={rmse:.3f}, MAE={mae:.3f}, Coverage={user_coverage:.2%}"
    logger.info(status)

    return status


# =============================================================================
# KEY CONCEPTS
# =============================================================================
#
# 1. MODEL INPUT ARTIFACT
#    - Input[Model]: Receives model from previous pipeline step
#    - Load using pickle.load() from model.path
#    - Contains all model data (factors, encoders, etc.)
#
# 2. EVALUATION METRICS
#    - RMSE (Root Mean Squared Error): Measures average prediction error
#      Lower is better. Scale: same as ratings (1-5)
#    - MAE (Mean Absolute Error): Average absolute prediction error
#      More interpretable than RMSE
#    - Coverage: % of test users/movies that were in training set
#      Measures cold-start problem severity
#
# 3. COLD-START PROBLEM
#    - Can't predict for users/movies not in training set
#    - Skip these in evaluation (or use content-based fallback)
#    - Coverage metric shows how often this happens
#
# 4. COMPONENT RETURN VALUES
#    - Components can return simple types (str, int, float, bool)
#    - Return value becomes available to downstream components
#    - Use for status messages, decisions, simple metrics
#
# 5. PREDICTION PROCESS
#    - Look up user_id in user_encoder → get user_idx
#    - Look up movie_id in movie_encoder → get movie_idx
#    - Compute: user_factors[user_idx] @ movie_factors[movie_idx]
#    - Clip to valid rating range [1.0, 5.0]
#
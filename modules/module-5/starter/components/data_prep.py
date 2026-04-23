"""
Exercise 1: Data Preparation Component for Kubeflow Pipeline
==============================================================

What you'll learn:
- Kubeflow component decorator and configuration
- Input/Output artifact types (Dataset)
- Data downloading and preprocessing
- Train/test split for ML pipelines

Instructions:
Fill in the 8 TODOs marked with '????' or '# YOUR CODE HERE'
Each TODO has inline hints showing exactly what to use.
"""

from kfp.dsl import component, Output, Dataset


# TODO 1: Complete the @component decorator
# HINT: Set base_image to "python:3.11-slim"
# HINT: Set packages_to_install to ["pandas==2.0.3", "scikit-learn==1.3.2"]
@component(
    base_image="????",  # TODO 1: Set to "python:3.11-slim"
    packages_to_install=["????", "????"]  # TODO 1: Set to ["pandas==2.0.3", "scikit-learn==1.3.2"]
)
def prepare_data(
    train_data: Output[Dataset],
    test_data: Output[Dataset],
    dataset_size: str = "100k",
    test_ratio: float = 0.2,
    random_state: int = 42
):
    """
    Download and prepare MovieLens dataset

    Args:
        train_data: Output training dataset
        test_data: Output test dataset
        dataset_size: Size of dataset to download (100k, 1m, etc.)
        test_ratio: Fraction of data for test set
        random_state: Random seed for reproducibility
    """
    import urllib.request
    import zipfile
    import pandas as pd
    import os
    from sklearn.model_selection import train_test_split
    import logging

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # TODO 2: Set the dataset URL to "https://files.grouplens.org/datasets/movielens/ml-100k.zip"
    dataset_url = "????"  # YOUR CODE HERE
    zip_path = "/tmp/ml-100k.zip"

    logger.info(f"Downloading MovieLens dataset from {dataset_url}")

    # TODO 3: Download the dataset using urllib.request.urlretrieve(dataset_url, zip_path)
    # YOUR CODE HERE

    # Extract the zip file
    logger.info("Extracting dataset")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall("/tmp")

    # TODO 4: Load ratings data with pd.read_csv("/tmp/ml-100k/u.data",
    #         sep='\t', names=['userId', 'movieId', 'rating', 'timestamp'], engine='python')
    ratings = None  # YOUR CODE HERE

    logger.info(f"Loaded {len(ratings)} ratings")
    logger.info(f"Users: {ratings['userId'].nunique()}")
    logger.info(f"Movies: {ratings['movieId'].nunique()}")

    # TODO 5: Split into train/test using train_test_split(ratings, test_size=test_ratio, random_state=random_state)
    #         Unpack the result into train_df, test_df
    train_df, test_df = None, None  # YOUR CODE HERE

    logger.info(f"Train set: {len(train_df)} ratings")
    logger.info(f"Test set: {len(test_df)} ratings")

    # TODO 6: Save training data — train_df.to_csv(train_data.path, index=False)
    # YOUR CODE HERE

    # TODO 7: Save test data — test_df.to_csv(test_data.path, index=False)
    # YOUR CODE HERE

    logger.info(f"Data preparation complete")

# =============================================================================
# KEY CONCEPTS
# =============================================================================
#
# 1. KUBEFLOW COMPONENT DECORATOR
#    - @component() marks a Python function as a Kubeflow pipeline component
#    - base_image: Docker image to run the component in
#    - packages_to_install: Python packages to install at runtime
#
# 2. INPUT/OUTPUT ARTIFACTS
#    - Output[Dataset]: Declares an output artifact of type Dataset
#    - .path attribute: Path where the artifact should be saved
#    - Kubeflow manages artifact storage and passing between components
#
# 3. COMPONENT PARAMETERS
#    - Regular Python parameters become pipeline parameters
#    - Can have default values
#    - Passed to component when pipeline runs
#
# 4. DATA SPLITTING
#    - train_test_split() creates reproducible train/test splits
#    - random_state ensures same split across runs
#    - test_ratio controls split percentage
#

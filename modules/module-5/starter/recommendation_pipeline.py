"""
Exercise 3: Kubeflow Pipeline Orchestration
============================================
"""

from kfp import dsl, compiler
from kfp.dsl import pipeline
import sys
import os

# Import components
sys.path.append(os.path.dirname(__file__))
from components.data_prep import prepare_data
from components.train import train_model
from components.evaluate import evaluate_model


# TODO 1: Complete the @pipeline decorator
# HINT: name="movie-recommendation-pipeline"
# HINT: description="End-to-end pipeline for training and deploying movie recommendation model"
@pipeline(
    name="????",  # TODO 1: Set to "movie-recommendation-pipeline"
    description="????"  # TODO 1: Set to "End-to-end pipeline for training and deploying movie recommendation model"
)
def recommendation_pipeline(
    dataset_size: str = "100k",
    test_ratio: float = 0.2,
    n_components: int = 20,
    random_state: int = 42,
    deploy_model_flag: bool = False  # Set to False by default for workshop
):
    """
    Complete ML pipeline for movie recommendations

    Args:
        dataset_size: Size of MovieLens dataset (100k, 1m, etc.)
        test_ratio: Fraction of data for testing
        n_components: Number of latent factors for SVD
        random_state: Random seed for reproducibility
        deploy_model_flag: Whether to deploy the model (requires KServe)
    """

    # TODO 2: Call prepare_data(dataset_size=dataset_size, test_ratio=test_ratio, random_state=random_state)
    #         and store the result in data_prep_task
    data_prep_task = None  # YOUR CODE HERE

    # TODO 3: Set display name — data_prep_task.set_display_name("Prepare MovieLens Data")
    # YOUR CODE HERE

    # TODO 4: Call train_model() passing:
    #           train_data=data_prep_task.outputs["train_data"]
    #           n_components=n_components, random_state=random_state
    #         Store result in train_task
    train_task = None  # YOUR CODE HERE

    # TODO 5: Set display name and dependency for train_task
    #         train_task.set_display_name("Train Recommendation Model")
    #         train_task.after(data_prep_task)
    # YOUR CODE HERE (2 lines)

    # TODO 6: Call evaluate_model() passing:
    #           test_data=data_prep_task.outputs["test_data"]
    #           model=train_task.outputs["model"]
    #         Store result in eval_task
    eval_task = None  # YOUR CODE HERE

    # TODO 7: Set display name and dependency for eval_task
    #         eval_task.set_display_name("Evaluate Model")
    #         eval_task.after(train_task)
    # YOUR CODE HERE (2 lines)

    # Note: Deployment step is commented out for workshop
    # In production, you would uncomment this:
    #
    # with dsl.Condition(deploy_model_flag == True):
    #     from components.deploy import deploy_model
    #     deploy_task = deploy_model(
    #         model=train_task.outputs["model"],
    #         service_name="movie-recommender",
    #         namespace="default"
    #     )
    #     deploy_task.set_display_name("Deploy to KServe")
    #     deploy_task.after(eval_task)


# TODO 8: Complete the compile_pipeline function
def compile_pipeline(output_path: str = "recommendation_pipeline.yaml"):
    """
    Compile pipeline to YAML

    Args:
        output_path: Path to save compiled pipeline
    """
    # TODO 8: Compile the pipeline using compiler.Compiler().compile()
    #         Pass pipeline_func=recommendation_pipeline, package_path=output_path
    # YOUR CODE HERE (3 lines)

    print(f"Pipeline compiled to {output_path}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Compile Kubeflow pipeline")
    parser.add_argument(
        "--output",
        type=str,
        default="recommendation_pipeline.yaml",
        help="Output path for compiled pipeline"
    )

    args = parser.parse_args()

    # Compile pipeline
    compile_pipeline(args.output)


# =============================================================================
# KEY CONCEPTS
# =============================================================================
#
# 1. PIPELINE DECORATOR
#    - @pipeline() marks a function as a Kubeflow pipeline
#    - name: Pipeline name shown in Kubeflow UI
#    - description: Helpful description for users
#    - Function parameters become pipeline parameters
#
# 2. COMPONENT TASKS
#    - Calling a component creates a task: data_prep_task = prepare_data(...)
#    - Task has .outputs dictionary with artifact names
#    - Access outputs: data_prep_task.outputs["train_data"]
#
# 3. TASK DEPENDENCIES
#    - .after(other_task): Sets execution order
#    - Example: train_task.after(data_prep_task)
#    - Ensures data prep completes before training starts
#
# 4. TASK DISPLAY NAMES
#    - .set_display_name("Human Readable Name")
#    - Shows in Kubeflow UI instead of function name
#    - Makes pipeline graph easier to understand
#
# 5. CONDITIONAL EXECUTION
#    - with dsl.Condition(expression):
#    - Tasks inside only run if condition is True
#    - Useful for optional deployment, A/B testing, etc.
#
# 6. PIPELINE COMPILATION
#    - compiler.Compiler().compile() converts Python to YAML
#    - YAML can be uploaded to Kubeflow UI
#    - Or submitted via kfp.Client()
#
# =============================================================================
# PIPELINE FLOW
# =============================================================================
#
# 1. Data Preparation
#    ├─ Downloads MovieLens dataset
#    ├─ Splits into train/test
#    └─ Outputs: train_data, test_data
#
# 2. Model Training
#    ├─ Input: train_data (from step 1)
#    ├─ Trains SVD model
#    ├─ Logs metrics (RMSE, explained variance)
#    └─ Outputs: model
#
# 3. Model Evaluation
#    ├─ Inputs: test_data (from step 1), model (from step 2)
#    ├─ Evaluates model performance
#    ├─ Logs metrics (test RMSE, MAE, coverage)
#    └─ Returns: status message
#
# 4. Model Deployment (Optional)
#    ├─ Input: model (from step 2)
#    ├─ Deploys to KServe
#    └─ Returns: deployment status
#
# =============================================================================
# COMPILING AND RUNNING
# =============================================================================
#
# 1. COMPILE PIPELINE:
#    python recommendation_pipeline.py --output my_pipeline.yaml
#
# 2. SUBMIT TO KUBEFLOW:
#    import kfp
#    client = kfp.Client(host='http://localhost:8080')
#    client.create_run_from_pipeline_package(
#        'my_pipeline.yaml',
#        arguments={
#            'n_components': 20,
#            'test_ratio': 0.2
#        }
#    )
#
# 3. VIEW IN KUBEFLOW UI:
#    - Open http://localhost:8080
#    - Go to Pipelines > Runs
#    - Click on your run to see graph and logs
#

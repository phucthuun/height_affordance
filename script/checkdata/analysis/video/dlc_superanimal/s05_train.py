# # Transfer learning from SuperAnimal-HumanBody
# from deeplabcut.modelzoo import build_weight_init

# deeplabcut.merge_datasets(config_path)

# weight_init = build_weight_init(
#     cfg=config_path,
#     super_animal="superanimal_humanbody",
#     model_name="rtmpose_x",
#     detector_name="fasterrcnn_resnet50_fpn_v2",
#     with_decoder=False,   # required for the transfer_learning=True path below
# )

# deeplabcut.create_training_dataset(config_path, weight_init=weight_init)

# deeplabcut.train_network(
#     config_path,
#     epochs=100,                      # small correction set → don't need thousands of epochs
#     superanimal_name="superanimal_humanbody",
#     superanimal_transfer_learning=True,
# )

# deeplabcut.evaluate_network(config_path, plotting=True)


import deeplabcut

config_path = r"C:\Data\Research\10_Data\derivatives\dlc_superanimal\sub-Maximilian\ses-S001\heightaffordance-Phuc-2026-07-19\config.yaml"

# deeplabcut.merge_datasets(config_path)   # only proceeds once all folders show CollectedData_*.h5

# deeplabcut.create_training_dataset(config_path)  # no weight_init -> defaults to ImageNet-pretrained backbone

# deeplabcut.train_network(config_path, maxiters=20000, displayiters=100, saveiters=1000)  # budget more epochs than the transfer-learning path needed

deeplabcut.evaluate_network(config_path, plotting=True)
print("hello")

try:
    import torch
    cuda_available = torch.cuda.is_available()
    print(f"CUDA available: {cuda_available}")
    if cuda_available:
        gpu_count = torch.cuda.device_count()
        print(f"Number of GPUs: {gpu_count}")
        for i in range(gpu_count):
            print(f"  GPU {i}: {torch.cuda.get_device_name(i)}")
    else:
        print("Number of GPUs: 0")
except ImportError:
    print("PyTorch is not installed")

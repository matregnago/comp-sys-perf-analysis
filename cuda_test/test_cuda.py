import torch
import sys

print(f"Python: {sys.executable}")
print(f"PyTorch: {torch.__version__}")
print(f"CUDA disponível: {torch.cuda.is_available()}")
print(f"CUDA version: {torch.version.cuda}")
print(f"Quantidade de GPUs: {torch.cuda.device_count()}")

for i in range(torch.cuda.device_count()):
    props = torch.cuda.get_device_properties(i)
    print(f"  GPU {i}: {props.name}, {props.total_mem / 1024**3:.1f} GB")

if torch.cuda.is_available():
    x = torch.randn(1000, 1000, device="cuda")
    y = x @ x.T
    print(f"\nMatmul 1000x1000 na GPU: OK (resultado shape={y.shape})")

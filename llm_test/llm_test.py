import time
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

# =========================
# CONFIG
# =========================
MODEL_NAME = "gpt2"

PROMPT = "Explique complexidade de algoritmos de forma simples."
MAX_NEW_TOKENS = 100

# =========================
# SYSTEM INFO
# =========================
print("=== SYSTEM INFO ===")
use_gpu = torch.cuda.is_available()

print(f"CUDA available: {use_gpu}")
print(f"GPU count: {torch.cuda.device_count()}")

if use_gpu:
    print(f"GPU 0: {torch.cuda.get_device_name(0)}")

# =========================
# LOAD MODEL
# =========================
print("\nLoading tokenizer...")

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

print("Loading model (this may take time)...")

model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float16 if use_gpu else torch.float32,
    device_map="auto" if use_gpu else None
)

# 👉 garante que vai pro lugar certo
device = "cuda" if use_gpu else "cpu"
model.to(device)

model.eval()

# =========================
# TOKENIZE
# =========================
inputs = tokenizer(PROMPT, return_tensors="pt")
inputs = {k: v.to(device) for k, v in inputs.items()}

# =========================
# INFERENCE + TIMING
# =========================
print("\nRunning inference...")

start_time = time.time()

with torch.no_grad():
    output = model.generate(
        **inputs,
        max_new_tokens=MAX_NEW_TOKENS,
        do_sample=False
    )

end_time = time.time()

# =========================
# METRICS
# =========================
input_tokens = inputs["input_ids"].shape[1]
output_tokens = output.shape[1]

generated_tokens = output_tokens - input_tokens
total_time = end_time - start_time

tps = generated_tokens / total_time

# =========================
# RESULTS
# =========================
print("\n=== OUTPUT ===")
print(tokenizer.decode(output[0], skip_special_tokens=True))

print("\n=== METRICS ===")
print(f"Input tokens: {input_tokens}")
print(f"Generated tokens: {generated_tokens}")
print(f"Total latency (E2E): {total_time:.4f} s")
print(f"Throughput (TPS): {tps:.2f} tokens/s")
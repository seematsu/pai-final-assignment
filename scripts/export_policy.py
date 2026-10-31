"""Export policy weights from a training workspace checkpoint for LabUtopia local inference.

Training saves {'cfg', 'state_dicts': {'model', 'ema_model', 'optimizer'}, 'pickles'} with dill,
while controllers/inference_engines/local_model_inference_engine.py reads {'state_dict': ...}.
The exported file holds tensors only, so the inference side loads it with torch's weights_only default.

Usage: python scripts/export_policy.py <workspace.ckpt> <policy.ckpt> [--no-ema]
"""
import argparse

import dill
import torch


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("checkpoint")
    parser.add_argument("output")
    parser.add_argument("--no-ema", action="store_true", help="export the raw model instead of the EMA model")
    args = parser.parse_args()

    # Only our own training checkpoints are loaded here; they are dill pickles.
    payload = torch.load(args.checkpoint, map_location="cpu", pickle_module=dill, weights_only=False)
    key = "model" if args.no_ema or "ema_model" not in payload["state_dicts"] else "ema_model"
    state_dict = payload["state_dicts"][key]
    # The inference engine strips one leading "model." (multi-GPU wrapper) and drops keys containing "ema".
    state_dict = {f"model.{k}": v for k, v in state_dict.items()}
    torch.save({"state_dict": state_dict}, args.output)
    epoch = dill.loads(payload["pickles"]["epoch"]) if "epoch" in payload["pickles"] else "?"
    print(f"exported {key} (epoch {epoch}, {len(state_dict)} tensors) -> {args.output}")


if __name__ == "__main__":
    main()

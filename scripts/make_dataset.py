"""Build a training dataset directory (episode_data.hdf5) from collected run directories.

The LabUtopia ACT/DP datasets read <dataset_path>/episode_data.hdf5 with one group per episode.
By default each group is an HDF5 external link to the collected episode file, so nothing is copied.
Pass --copy to write a self-contained file, e.g. before transferring to another machine.

Usage: python scripts/make_dataset.py <out_dir> <run_dir> [<run_dir> ...] [--copy]
"""
import argparse
import glob
import os

import h5py


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out_dir")
    parser.add_argument("run_dirs", nargs="+")
    parser.add_argument("--copy", action="store_true")
    args = parser.parse_args()

    episode_files = []
    for run_dir in args.run_dirs:
        episode_files += sorted(glob.glob(os.path.join(run_dir, "dataset", "episode_*.h5")))
    if not episode_files:
        raise SystemExit("no episode_*.h5 found")

    os.makedirs(args.out_dir, exist_ok=True)
    out_path = os.path.join(args.out_dir, "episode_data.hdf5")
    with h5py.File(out_path, "w") as out:
        for i, path in enumerate(episode_files):
            name = f"episode_{i:04d}"
            if args.copy:
                group = out.create_group(name)
                with h5py.File(path, "r") as src:
                    for key in src.keys():
                        src.copy(key, group)
            else:
                out[name] = h5py.ExternalLink(os.path.abspath(path), "/")
    print(f"{len(episode_files)} episodes -> {out_path}")


if __name__ == "__main__":
    main()

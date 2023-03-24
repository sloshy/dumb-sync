# Example Transformations
The script files in this directory are all examples that you can use and build on for your own use.
More scripts can be contributed later as use cases develop.

## Example configuration
To give you a visual example of how transformations can be configured, here is an example use case:

I have a remote directory that has ZIP files containing archives of disc images, where each ZIP has the same name as the disc image inside.
I would like to synchronize it to my local directory while changing the archive structure from ZIP to CHD, to preserve the disc images while making them playable in emulators and such.
The following config specifies two transformations and the requisite parameters for them to work properly:

```json
{
  "transformations": [
    {
      "name": "7z",
      "script": "./7z_extract.sh",
      "params": [
        "<filename_in>",
        "<outdir>",
        "<arg:rm_file>"
      ]
    },
    {
      "name": "chd",
      "script": "./chd.sh",
      "params": [
        "<outdir_abs>",
        "true"
      ]
    }
  ],
  "cleanup_transformations": [
    {
      "name": "7z-cleanup",
      "script": "./7z_extract_cleanup.sh",
      "params": [
        "<outdir>",
        "<arg:rm_file>"
      ]
    },
    {
      "name": "chd-cleanup",
      "script": "./chd.sh",
      "params": [
        "<outdir_abs>",
        "true"
      ]
    }
  ],
  "comparisons": [
    {
      "name": "expected_ext",
      "script": "./comparisons/expected_ext.sh",
      "params": [
        "<file_list>",
        "<filename_local>",
        "<arg:ext_remote>",
        "<arg:ext_local>",
        "<last_sync_time_secs>",
        "<sync_offset_secs>"
      ]
    }
  ],
  "config": [
    {
      "remote": "some/dir/",
      "local": "some/dir/",
      "transforms": ["7z", "chd"],
      "cleanup": ["7z-cleanup", "chd-cleanup"],
      "comparison": "expected_ext",
      "ext_remote": "zip",
      "ext_local": "chd",
      "rm_file": true
    }
  ]
}
```

The above config will take the `rm_file` property from the current `config` and extract each individual archive to the output folder.
The input file extension is set to `zip` and the output to `chd`, so that the sync script can keep track of which files were synchronized properly after transformation.

The end result is that the synchronized directory will be kept in-sync with the remote, by comparing the file names according to the specified extensions, and keeping track of when a sync was last performed to determine if the file should be updated.

Below are details on the included example scripts, with information on how they work and how you can come to write your own.

## 7z_extract
Extracts a file using 7zip (p7zip on POSIX systems) on the command line.
Usage:
```
./extract_7z.sh <in_file> <out_dir> <rm_archive>
```
The file specified as `<in_file>` is extracted with all of its contents to the specified `<out_dir>`.
If `<rm_archive>` is set to `true`, it will also remove the original archive file.
This can be very useful if, for example, you are synchronizing a directory of archives that you wish to extract first.

**Important**: If you extract an archive into the same directory, be sure to set the `ext_remote` and `ext_local` options so the main 
sync script can keep track of the file names as the extensions change.

Also, this uses the 7z `e` option which does **not** preserve folder structure, but instead dumps all of the files into this directory.
If you would like to preserve the file structure, simply edit the script to use `7z x` instead of `7z e`.

## 7z_extract_cleanup
A modified version of the above script that extracts every file in a directory, rather than a single file.
```
./extract_7z_cleanup.sh <dir> <rm_archive>
```
All of the same notes and caveats apply as above.

## rm_file
Removes a specified file by-name.
This is an example of a script that is not very useful on its own but can be easily modified using custom rules and settings.

For example, assume you are extracting an archive using one of the above scripts, but that archive has several junk files with some extension. You can modify the script to instead remove all files with that extension as follows:
```bash
#!/usr/bin/env bash

set -e

# Get the substring of 
RM_EXT=$1

rm -f *."$RM_EXT"
```

## chd
A more specific example that shows using `sudo` as well as `docker` to run a script inside an existing container image.
This script runs the `marctv/chd-converter` image, which will scan the input directory for "BIN/CUE" files (also GDI and ISO) to turn them into "CHD" files, a format used by the MAME project for efficient archival of disc images while keeping them playable in real-time due to minimizing decompression overhead.

You may find this script useful if you have a lot of backups of disc images that you want to synchronize, while reducing the amount of space they take up at the target destination.

```
./chd.sh <out_dir> <rm_original_files>
```

The `<out_dir>` must be an absolute path, so if you are using this script as a transformation and wish to output to a target directory, simply use the `<outdir_abs>` keyword in the params list, as specified in the main README.
If `<rm_original_files>` is set to true, then the script will delete **all** BIN, CUE, GDI and ISO-format files in the directory you specify.
This should be okay for most uses as you can recover those formats from the resulting CHD losslessly, but to make you aware this will happen, it is an opt-in flag that should be specified explicitly.

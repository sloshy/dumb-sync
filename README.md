# Dumb Sync
Dumb Sync is a sort of micro-framework for using `rsync` to synchronize files across multiple directories and machines.
This project was born out of a need to have slightly-varying synchronizations across multiple folders, including a desire to transform the synchronized files in some cases while still keeping them in sync.

## Main Features
* Unidirectional synchronizing folders via `rsync`
* Per-file and per-folder transformation scripts
* Custom script argument support per-config
* Program variables (such as current file/time/output directory) support for scripts
* `sudo` support for transformations to pass your password along to scripts as necessary
* Date-time-based synchronization of transformed files using a stored time offset
* Optional removal of deleted files from remote based on file listing

A good use-case for using this sync script is if you have multiple target folders to sync, each with slightly varying transformations you wish to apply to some or each of them.
When you have a file sync + transformation use-case that spans more than a few folders and shared scripts between them, things can get a little complicated without a script framework in place like this one.

## Install & Requirements
Before using, make sure you have a modern version of Bash as well as `rsync` and `jq` installed on your system.
```bash
hash rsync || echo "rsync not installed"
hash jq || echo "jq not installed"
```

Also manually check that you have a Bash version >= 4.3

```bash
bash --version
```

Download the latest `sync.sh` from this repository and make sure it is marked as executible

```bash
wget https://raw.githubusercontent.com/sloshy/dumb-sync/main/sync.sh
chmod +x sync.sh
```

Or, you can click the big green "Clone" button and "download as ZIP" a copy of the entire repository to get the latest version of every file.
Then, make sure that every `.sh` file you would like to use is marked executible using a command similar to the above.

Next, create a file in the same directory named `sync.json`.
You can follow the template in the included [`sync.json`](/sync.json) or you can create one yourself.

For a more fleshed-out example, see the [example_transformations](/example_transformations/) directory which has a more motivated example of how you can chain transformation scripts together while keeping the resulting files in sync.

## Configuration
To use the sync script, you need a configuration file with the proper settings.
Required settings are as follows:
* `remote_url` or `remote_urls` - One or more rsync-compatible locations for files. Can be another directory on this local machine, or an rsync-compatible URL such as `rsync://some-host/` or `me@example.com:/some/dir/`. For syncing folders, **be sure this ends in a trailing slash**. If you have a single URL, specify it as `remote_url` and by default all of your configs will use this url for syncing. For multiple URLs, you can create an object in an array named `remote_urls` to designate the URL with a name.
* `log_dir` - The directory for storing log files. Defaults to the current directory if not set. Trailing slashes are stripped and implied at runtime.
* `file_list_dir` - The directory for storing rsync file lists. Defaults to `log_dir` if not set. Trailing slashes are stripped and implied at runtime.
* `sync_offset_seconds` - A number of seconds to offset date-time checking for transformed files. This defaults to 0, and file times should usually be preserved across remote and local directories, so you almost never need to modify this.
* `configs` - An array of individual sync configs, described below.

Each URL defined in `remote_urls` has two required parameters:
* `name` - A friendly name for the URL, for selecting in each of your configs.
* `url` - The rsync URL of the location you are syncing from.

Each sync config in the `configs` array requires the following options:
* `remote` - An additional suffix to append to the base `remote_url` specified above. For example, if you are syncing from `rsync://some.remote.server/files/`, you could add `some/dir/` to make the final sync URL equal `rsync://some.remote.server/files/some/dir/`.
* `local` - The local directory to sync files to. It is recommended to **not** use the current directory as some settings can cause the sync program to inadvertedly remove program files. Also, any trailing slashes are stripped and implied at runtime.
* `disabled` - Whether to run the current config. Defaults to `false`, but can be set to `true` to skip the current config.

You can also supply these optional settings:
* `url_name` - A specific remote URL to use. If specified, uses the URL as named in the `remote_urls` array in the root of the config. If not specified, your config will use the default URL specified in `remote_url` if defined. Otherwise, it will fail.
* `exclude` - An array of rsync-compatible exclusions for the current sync config. For example, a setting of `["Something*", "*Something"]` will exclude files that start and end with the string `Something` in their name.
* `include` - An array of rsync-compatible includions for the current sync config, for usage in conjunction with exclusions above. These are applied before exclusions.
* `transforms` - An array of the names of transformation scripts to apply in-order. These are ran on a per-file basis.
* `cleanup` - An array of the names of cleanup transformation scripts to apply in-order. These are ran once at the end of synchronizing files.
* `comparison` - The name of a `comparison` script to run for determining whether or not a file is `missing`, `updated`, or `current`. An example is defined in this repository for keeping files with modified extensions in sync with the originals, defined in more detail below.
* `max_size_bytes` - The upper limit in file size for syncing. Files over this size in bytes will not be synced.
* `min_size_bytes` - The lower limit in file size for syncing. Files under this size in bytes will not be synced.
* `rm_missing` - A boolean flag for whether or not to remove files that are available locally but missing from the remote sync directory. Defaults to false, but should usually be set to `true` for cases where you want to keep a clean sync directory.

For the `max_size_bytes`/`min_size_bytes` options, this only affects syncing and it does not affect the file lists used for comparisons.
This means, for example, if you have a file locally that has the same name as a file being excluded due to the size limit, it will not be deleted if you also specify `rm_missing`.

You can also supply arbitrary properties for usage as transformation and comparison parameters, described below.

### Transformations

Transformations are listed in two places in the root of the config:
* `transformations` - Definitions of scripts to run on a per-file basis.
* `cleanup_transformations` - Definitions of scripts to run once after syncing is completed.

None of these transformations are ran without being explicitly invoked by a config object definition.
For example, if you have a config that does not specify any transformations, a traditional 1:1 sync will be performed.
If instead, you define your transformations array in the config as `["script-a", "script-b"]`, then for each file that is synchronized it will run the transformation named `script-a` followed by `script-b`, once per-file.
If these scripts are set for the `cleanup` array instead, the scripts will be ran once.

Each transformation is defined as follows:
* `name` - A friendly name for the transformation, separate from the actual script name. This is the name you supply in the sync configs above.
* `script` - The location of the executible file or script to run when this is invoked. Files in the same directory can be invoked as `./script-name.sh`.
* `params` - An ordered list of arguments that the script accepts, described below.
* `sudo` - A boolean flag as to whether or not the script expects to be ran with `sudo`. Defaults to false. If set to true, your `sudo` password will be supplied to the script via standard input, so you should make sure your script handles this appropriately. For an example of handling `sudo` passwords from standard input, see the included [`chd.sh`](/example_transformations/chd.sh) script that uses Docker, which is usually limited to root users for security reasons.

The `params` section defines the list of parameters that will be supplied in order to the script.
You can supply arbitrary strings, or you can use special keywords to pass runtime variables and your own config settings to the script.
These keywords available for transformations are as follows:
* `<outdir>` - Passes the configured output directory (`local`) for the current config.
* `<outdir_abs>` - The absolute path of the configured output directory. This is determined by prefixing the directory with the results of the `pwd` command, so if your output directory is already absolute and not relative, you should not use this.
* `<file_list>` - A file containing the most recent list of files from the remote directory, synchronized by rsync. This list is saved *before commencing the sync* so it is possible for it to be outdated in later steps. This is primarily used for checking existing files before syncing, and is mostly useful in comparisons, rather than transformations.
* `<filename_remote>` - The filename of the remote file being synchronized, prefixed by the current output directory. **Not valid for cleanup scripts.** If the current file is `my-file.txt` and the currently-set `local` output directory is `some/dir/`, the parameter will be rendered as `some/dir/my-file.txt`.
* `<filename_remote_base>` - The base name of the current file, including its extension. **Not valid for cleanup scripts.** Does not include any path information.
* `<last_sync_time_secs>` - The UNIX epoch timestamp in seconds-since-1970-01-01 that the last sync was performed. Useful for keeping transformed files in sync with remote ones when local file timestamps might not be reliable (for example, if you are syncing a file that might become modified for unrelated reasons, that you would prefer to sync from scratch each time).
* `<current_time_secs>` - The current timestamp (same format as above).
* `<sync_offset_secs>` - The number of seconds of the sync offset defined in your root config. Typically 0, but could be different, so for some scripts you want to make sure you include this parameter any time you are dealing with time offsets.
* `<arg:some_arg>` - The literal value of the property `some_arg` in the current config. Can be used to pass per-config settings into the script that might vary based on your use-cases. For example, to get the expected starting file extension (if defined), use `<arg:ext_remote>` to copy the value of `ext_remote` as an argument to the script.
* You can also supply literal text to have it passed verbatim as an argument.

For some ideas on how you can configure the transformations, see the [example transformations](/example_transformations/) directory.

### Comparisons
Comparisons are a way to keep your files in sync even if they are transformed.
They work in conjunction with the `rm_missing` option to help determine whether or not a file exists in the state you desire on your local machine, and also with transformations by limiting the scope of transformations to updated or freshly-synchronized files only.

The way that `rsync` usually works is that it compares the file names and modified times across hosts.
If you are transforming the files, or deleting the original files as part of transformation, this will no longer work, so to keep them in sync the script will make use of one or more comparison techniques that you can customize yourself with scripts.

The default comparison method uses the built-in `rsync` file name and modification checking, but to opt into a different form of comparison, you can specify a dedicated comparison script in the `comparisons` array in the root of your config.
The included example config specifies [one such script](/comparisons/expected_ext.sh) that takes a variety of parameters in order to determine whether or not a file in the output directory counts as `missing`, `current`, or `updated`. Each `current` file is excluded from the upcoming sync, while `updated` files are removed and redownloaded and `missing` files are either explicitly ignored as a "preexisting file" that should not be transformed, or removed outright if the `rm_missing` option is enabled.

To configure a comparison, simply add an object much like a `transformation` or `cleanup_transformation` object inside the `comparisons` array, and configure it in the same sort of way, with the same options, except for `sudo` which is not supported for comparisons intentionally.

A single comparison can be set for each sync configuration, unlike transformations or cleanup transformations.
This single script will be ran if defined, and its return value must be either `missing`, `transform`, `current`, or `updated` for every file in the output directory.
Each case has certain properties:

* `missing` - This file is present locally, but not on the remote destination. Will be removed if `rm_missing` is enabled.
* `transform` - This file is present locally, but it is still in its initial state. Will not exclude the file from syncing if it's updated and will transform as normal.
* `current` - This file is derived/transformed from a remote file, and it is up-to-date. It is excluded from sync and per-file transformations.
* `updated` - This file is derived/transformed from a remote file, but it is not up-to-date with the remote source. It will be deleted, redownloaded, and transformed again.

For the `current` case, it actually needs to be specified as `current <remote_file_name>`, where `<remote_file_name>` is the name of the file you are deriving your final, local file from after all your transformations.
This is so that the sync script can explicitly exclude this file from sync.

If a comparison is not specified, only removing nonexistent files is taken into account if specified, so be sure to specify a comparison if your local output directory is likely not a 1:1 match to your remote folder.

Comparisons support some special keywords as parameters, and do not support some keywords that are supported for transformations.
Here is the list of keywords that are **only valid for comparisons**:

* `<filename_local>` - The local filename that is being checked for comparison. Is prefixed by the local path specified in the current config.
* `<filename_local_base>` - The local filename that is being checked for comparison, without any path information.

The following keywords are **not valid for comparisons**:

* `<filename_remote>`
* `<filename_remote_base>`

This is due to the internal logic at the time of comparison only being over the files in the local output directory, and not over the list of files from the remote source.
For the list of remote files, use the `<file_list>` keyword instead, which you can search and interpret as you see fit.

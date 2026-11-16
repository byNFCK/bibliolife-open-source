# Library transition benchmark safety

The Library transition harness is an opt-in diagnostic tool. It must not be
used as the normal application entrypoint or as a substitute for a regular
APK build.

Before any physical-device run:

1. Record `pm path`, package install timestamps, process/activity state, and
   the app data file list.
2. Back up the app data that is accessible through `run-as`, especially the
   Drift database and any book or cover files.
3. Use a dedicated benchmark APK/target and keep it installed with
   `--keep-app-running`; do not use a default integration-test command that
   can uninstall the package during teardown.
4. Never use `pm clear` or uninstall as part of the benchmark workflow.
5. After the run, build the regular app explicitly from `lib/main.dart` and
   restore it in place with `adb install -r` before functional validation.

Benchmark-only `--dart-define` flags must remain false by default. The
diagnostic code must not register frame callbacks or inspect cover files when
those flags are disabled.

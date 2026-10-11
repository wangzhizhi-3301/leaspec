# Script regression tests

Tests run the real scripts against temporary projects and clean up afterwards.
They require Python 3, PyYAML (test-only), and Bash 4+ as required by `init.sh`.

```sh
python3 -m pip install -r tests/requirements.txt
python3 -m unittest discover -s tests -v
```

On macOS, select a Bash 4+ executable instead of the system Bash 3.2:

```sh
BASH_BIN=/opt/homebrew/bin/bash python3 -m unittest discover -s tests -v
```

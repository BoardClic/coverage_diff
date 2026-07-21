# CoverageDiff

A Mix task for Elixir that generates test coverage reports showing only the lines you changed. Stop worrying about overall project coverage and focus on whether your new code is tested.

## Why CoverageDiff?

Traditional coverage reports show coverage for your entire codebase. CoverageDiff focuses on what matters during development: **are the lines you just added or modified covered by tests?**

This is especially useful for:

- **Code reviews** - Quickly identify untested changes in pull requests
- **CI/CD pipelines** - Enforce coverage requirements only on changed code
- **Large codebases** - Don't let legacy code's low coverage block new, well-tested features
- **Incremental improvement** - Keep new code quality high without requiring a full codebase refactor
- **LLM-assisted development** - Provides focused, relevant coverage data that fits within context windows and helps AI assistants give better feedback on test coverage

## Features

- Shows coverage only for changed lines compared to a base branch
- Generates a beautiful HTML report with side-by-side diff view
- Highlights uncovered changes in the terminal
- Respects your existing `coveralls.json` skip patterns
- Configurable context lines around changes
- Works with any Elixir project using ExCoveralls

## Installation

Add `coverage_diff` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:coverage_diff, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Usage

### Basic Usage

Generate a coverage report for all changes compared to `main`:

```bash
mix coveralls.diff
```

### Compare Against a Different Branch

```bash
mix coveralls.diff --base develop
```

### Customize Output Location

```bash
mix coveralls.diff --output cover/my_report.html
```

### Adjust Context Lines

Show more or fewer lines around changes (default is 3):

```bash
mix coveralls.diff --context 5
```

### Hide Fully-Covered Files

Show only files that still have uncovered changes. The reported coverage
percentage still reflects all changed lines:

```bash
mix coveralls.diff --hide-covered
```

### Pass Arguments to Coveralls

Pass additional arguments to the underlying `mix coveralls.json` command after `--`:

```bash
# Exclude integration tests
mix coveralls.diff -- --exclude integration

# Run only specific tests
mix coveralls.diff -- --only unit

# Combine options
mix coveralls.diff --base develop --output cover/pr_coverage.html -- --exclude slow
```

## Command Line Options

| Option | Alias | Default | Description |
|--------|-------|---------|-------------|
| `--base` | `-b` | `main` | Base branch to compare against |
| `--output` | `-o` | `cover/diff_coverage.html` | Output path for HTML report |
| `--context` | `-c` | `3` | Number of context lines to show around changes |
| `--hide-covered` | `-H` | `false` | Omit files whose changed lines are fully covered |

## How It Works

1. Runs `mix coveralls.json` to generate coverage data
2. Reads the coverage data from `cover/excoveralls.json`
3. Gets the git diff between your current branch and the base branch
4. Filters coverage to only changed lines (plus context)
5. Generates an HTML report showing coverage for changed code
6. Prints a summary to the console with uncovered line numbers

## CI/CD Integration

### GitHub Actions

```yaml
name: PR Coverage Check

on: [pull_request]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Needed for git diff

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '27'

      - run: mix deps.get
      - run: mix coveralls.diff --base origin/${{ github.base_ref }}

      - uses: actions/upload-artifact@v3
        if: always()
        with:
          name: coverage-report
          path: cover/diff_coverage.html
```

### GitLab CI

```yaml
coverage:
  stage: test
  script:
    - mix deps.get
    - mix coveralls.diff --base origin/main
  artifacts:
    paths:
      - cover/diff_coverage.html
    when: always
```

## Configuration

CoverageDiff respects your existing `coveralls.json` configuration, including `skip_files` patterns:

```json
{
  "coverage_options": {
    "minimum_coverage": 80
  },
  "skip_files": [
    "test/",
    "priv/repo/migrations/"
  ]
}
```

Files matching skip patterns will be excluded from the diff coverage report.

## Output Example

Terminal output:

```
Running tests with coverage...
Analyzing coverage for changed files...

Changed Lines Coverage: 87.5% (14/16)

Uncovered changes:
  lib/my_module.ex:42 (1 line)
  lib/my_module.ex:58-60 (3 lines)

Report: cover/diff_coverage.html
```

The HTML report includes:
- Overall coverage percentage for changed lines
- File-by-file breakdown with coverage percentages
- Side-by-side diff view with coverage highlighting
- Line-by-line coverage status (covered, uncovered, not relevant)

## Development

```bash
# Clone the repository
git clone https://github.com/boardclic/coverage_diff.git
cd coverage_diff

# Install dependencies
mix deps.get

# Run tests
mix test

# Generate coverage for this project
mix coveralls.diff
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Credits

Built with:
- [ExCoveralls](https://github.com/parroty/excoveralls) - Coverage reporting for Elixir
- [Jason](https://github.com/michalmuskala/jason) - JSON parser

Copyright (c) 2026 BoardClic AB

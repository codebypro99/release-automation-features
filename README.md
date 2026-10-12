# Release Automation Feature Samples

Two independent CI/CD excerpts demonstrating Android packaging and commit-based application version calculation.

## Purpose

These samples show how I express release rules as reviewable configuration and scripts: test gates, packaging conditions, signing inputs, semantic version classification, and build metadata.

## Android CI and Packaging

**Source:** [android.yml](./features/android.yml)

A GitHub Actions workflow for a workspace containing shared core code, a mobile web application, and Android modules.

- Runs on main-branch pushes and pull requests, version-tag pushes, and manual dispatch.
- Configures Node.js 22 and Java 21, with npm and Gradle caching.
- Builds the core workspace and runs core, mobile, and SSH-engine JVM tests.
- Installs an SSH server for the engine's integration tests.
- Gates the packaging job on successful tests and limits it to tags or manual dispatch.
- Derives Android versionName from a tag and versionCode from the workflow run number for tag builds.
- Builds the web application and synchronizes Capacitor.
- Decodes a signing keystore from a repository secret when supplied.
- Passes signing configuration through environment variables to Gradle.
- Assembles APK and AAB outputs and uploads both as workflow artifacts.
- Creates or reuses a GitHub release and attaches the APK for tag builds.

**What this demonstrates:** separating validation from packaging and distinguishing manual artifact generation from tag-triggered release publication.

**Excerpt context:** package scripts, Gradle configuration, workspace sources, signing behavior, and SSH test fixtures are outside this file. The workflow requests repository contents write permission. Signing without secrets depends on the surrounding Gradle configuration. It uploads the APK to a release; it does not upload the AAB to Google Play.

## Semantic Version and Build Metadata

**Source:** [compute-version.sh](./features/compute-version.sh)

A shell script that calculates the next version from final release tags and conventional commit messages.

- Attempts to fetch tags and selects the highest version-sorted tag matching `vMAJOR.MINOR.PATCH`.
- Classifies breaking markers as a major bump, feature commits as a minor bump, and other changes as a patch bump.
- Recognizes optional bullet prefixes in commit text, supporting squash-merge message bodies.
- Accepts an explicit major, minor, or patch override through RELEASE_TYPE.
- Starts at 1.0.0 when no final release tag exists.
- Produces a plain next version on main and a `-stage.<sha8>` suffix on every other branch.
- Appends the short commit SHA to main-branch Docker image tags.
- Writes version and image-tag metadata to files consumed by the surrounding pipeline.
- Rejects an unreleased changelog whose title duplicates an existing versioned changelog title.

**What this demonstrates:** making version selection, branch suffixes, and release metadata explicit in a reusable pipeline step.

**Excerpt context:** this script assumes backend and frontend directories exist and writes files in its working directory. It does not create or push a release tag. SHA-suffixed image names distinguish commits, but registry-side tag immutability is not enforced by the script. Its opening comment says the image tag equals the version; the implementation appends a SHA on main.

## Technologies

GitHub Actions, YAML, Node.js workspace commands, Java, Gradle, Capacitor, shell scripting, Git tags, conventional commit classification, and GitHub CLI release commands.

## About This Collection

The two excerpts come from different pipeline contexts and are documented independently. Original contents are preserved. The workflow is stored under `features/` as a portfolio sample, so it is not registered as an active GitHub Actions workflow in this repository.

Descriptions are based on source inspection. No build, packaging, signing, publishing, or version-script execution was performed for this collection.

## Portfolio Message

I can organize release automation around explicit test gates, artifact packaging, configurable signing inputs, and traceable version metadata.

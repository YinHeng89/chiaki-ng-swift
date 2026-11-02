# ``ChiakiDiagnostics``

Logging, redaction, API capture and error reports, with no global state.

## Overview

`ChiakiDiagnostics` depends only on `ChiakiModels` and the swift-dependencies library. The App composition
root builds one ``LogPipeline`` over a ``LogSettingsStore`` backed by the settings table and installs its
``LogPipeline/logger``, ``LogPipeline/settingsClient`` and ``LogPipeline/liveLogClient`` as the live values
of `\.logger`, `\.logSettings` and `\.liveLog`. Reducers and clients read `@Dependency(\.logger)`; other
types take a ``LoggerClient`` in their initialiser. Tests get ``LoggerClient/disabled`` unless they install
their own.

Everything written to disk passes through the one ``LogRedactor`` and the one ``RotatingLogFile``.

## Topics

### Logging

- ``LoggerClient``
- ``LogEvent``
- ``LogArea``
- ``LogSource``
- ``VideoDynamicRange``
- ``PlaybackLogRoute``
- ``LogPipeline``
- ``LogSettingsStore``
- ``LogSettingsClient``
- ``LogFormat``
- ``CoreDiagnosticLine``
- ``StreamFailureDiagnostics``

### Destinations

- ``FileLogSink``
- ``SystemLogSink``
- ``RotatingLogFile``
- ``APICaptureStore``

### Redaction

- ``LogRedactor``
- ``APICaptureRedactor``

### Live log

- ``LiveLogClient``
- ``LiveLogSnapshot``
- ``LiveLogEntry``

### Error reports

- ``ErrorReport``
- ``ErrorReportEnvironment``

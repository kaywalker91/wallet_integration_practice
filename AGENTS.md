# Repository Guidelines

## Project Structure & Module Organization
- `lib/` contains the Flutter app, organized by clean architecture: `core/`, `data/`, `domain/`, `wallet/`, and `presentation/`.
- `test/` holds unit and widget tests; name files like `*_test.dart`.
- `assets/` stores images/icons (registered in `pubspec.yaml`); keep new assets under the existing folders.
- `android/` and `ios/` contain platform-specific projects; `docs/` has supplemental notes.
- `build/` and `coverage/` are generated artifacts and should not be edited directly.

## Build, Test, and Development Commands
- `flutter pub get` installs dependencies.
- `dart run build_runner build --delete-conflicting-outputs` generates code (freezed/json_serializable/riverpod).
- `flutter run` starts the app on a connected device or emulator.
- `flutter test` runs the full test suite; `flutter test test/widget_test.dart` runs a single file.
- `flutter analyze` checks lints from `analysis_options.yaml`.
- `dart format .` formats Dart sources with standard styling.
- `flutter build apk --debug` or `flutter build apk --release` produces Android builds.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (based on `flutter_lints`); keep analyzer warnings at zero.
- Use 2-space indentation and run `dart format .` before committing.
- File names are `snake_case.dart`; classes are `UpperCamelCase`; methods/vars are `lowerCamelCase`.
- Constants also use `lowerCamelCase` per `constant_identifier_names`.

## Testing Guidelines
- Use Flutter's built-in test framework in `test/` with `_test.dart` names.
- Prefer unit tests for services/adapters and widget tests for UI flows.
- Use `mockito`/`mocktail` for external dependencies or platform services.

## Commit & Pull Request Guidelines
- Commit messages follow Conventional Commits seen in history: `feat(wallet): ...`, `fix(walletconnect): ...`, `docs: ...`, `refactor(wallet): ...`.
- PRs should include a concise summary, linked issue (if any), test results, and tested platforms.
- Provide screenshots or recordings for UI or wallet-flow changes.
- Call out any `.env` or WalletConnect configuration changes explicitly.

## Security & Configuration Tips
- Keep secrets in `.env`; never commit real keys. Add `.env.example` for new variables.
- Review `SECURITY_PLAN.md` for API key restrictions and release obfuscation guidance.

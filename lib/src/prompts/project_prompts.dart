import 'package:dart_mcp/server.dart';

void registerProjectPrompts(MCPServer server) {
  if (server is! PromptsSupport) return;
  final prompts = server;

  // 1. asset_cleanup prompt
  prompts.addPrompt(
    Prompt(
      name: 'asset_cleanup',
      title: 'Audit, optimize, and clean up Flutter assets',
      description:
          'Runs a comprehensive health check on Flutter assets, identifies unused or oversized files, '
          'optimizes images with WebP compression, and regenerates constant classes.',
      arguments: [
        PromptArgument(
          name: 'project_path',
          title: 'Project Path',
          description: 'Absolute path to the Flutter project root directory.',
          required: true,
        ),
      ],
    ),
    (request) {
      final projectPath = request.arguments?['project_path'] ?? '.';
      return GetPromptResult(
        description: 'Complete Flutter asset cleanup and optimization workflow.',
        messages: [
          PromptMessage(
            role: Role.user,
            content: TextContent(
              text:
                  'Please perform a full asset cleanup and optimization for the Flutter project at `$projectPath`:\n\n'
                  '1. Run `assetgenie_audit_health` to detect missing references, heavy assets (>300 KB), and unused files.\n'
                  '2. Run `assetgenie_audit_variants` to check for missing 2.0x/3.0x image scales or uncompiled SVGs.\n'
                  '3. Run `assetgenie_optimize_images` (dry_run: true) to preview potential savings from WebP compression.\n'
                  '4. Summarize all findings and recommend any safe deletions of unused assets before regenerating constants with `assetgenie_generate_constants`.',
            ),
          ),
        ],
      );
    },
  );

  // 2. add_language prompt
  prompts.addPrompt(
    Prompt(
      name: 'add_language',
      title: 'Add a new language / locale to Flutter project',
      description:
          'Guides adding a new locale to the project, translating missing ARB keys while preserving ICU placeholders.',
      arguments: [
        PromptArgument(
          name: 'project_path',
          title: 'Project Path',
          description: 'Absolute path to the Flutter project root directory.',
          required: true,
        ),
        PromptArgument(
          name: 'target_locale',
          title: 'Target Locale',
          description: "Target locale code to add (e.g. 'de', 'es', 'ja', 'fr').",
          required: true,
        ),
      ],
    ),
    (request) {
      final projectPath = request.arguments?['project_path'] ?? '.';
      final targetLocale = request.arguments?['target_locale'] ?? 'es';
      return GetPromptResult(
        description: 'Workflow to localize the Flutter application into a new language.',
        messages: [
          PromptMessage(
            role: Role.user,
            content: TextContent(
              text:
                  'I want to add support for locale `$targetLocale` to the Flutter project at `$projectPath`.\n\n'
                  '1. Run `assetgenie_audit_localization` to see all current translation keys from the primary locale.\n'
                  '2. Run `assetgenie_translate_localization` to translate missing keys into `$targetLocale`, ensuring all ICU placeholders ({name}, {count}) are strictly preserved.\n'
                  '3. Verify with `assetgenie_audit_localization` that no keys or placeholders are mismatched.',
            ),
          ),
        ],
      );
    },
  );

  // 3. localize_ui prompt
  prompts.addPrompt(
    Prompt(
      name: 'localize_ui',
      title: 'Extract hardcoded Text() widgets into ARB and localize widgets',
      description:
          'Finds hardcoded strings in Dart files, creates ARB keys, and rewrites widget code to use AppLocalizations.',
      arguments: [
        PromptArgument(
          name: 'project_path',
          title: 'Project Path',
          description: 'Absolute path to the Flutter project root directory.',
          required: true,
        ),
      ],
    ),
    (request) {
      final projectPath = request.arguments?['project_path'] ?? '.';
      return GetPromptResult(
        description: 'Workflow to extract UI strings into ARB and replace them with AppLocalizations.',
        messages: [
          PromptMessage(
            role: Role.user,
            content: TextContent(
              text:
                  'Please scan the Flutter project at `$projectPath` for hardcoded UI strings:\n\n'
                  '1. Run `assetgenie_extract_strings` (with `dry_run: true`) to find all hardcoded `Text(...)` widgets.\n'
                  '2. Inspect the proposed ARB keys and parameter placeholders.\n'
                  '3. Ask for confirmation, then run with `dry_run: false` and `apply_rewrites: true` to localize the widgets.',
            ),
          ),
        ],
      );
    },
  );
}


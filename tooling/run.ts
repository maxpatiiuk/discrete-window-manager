import { parseArgs } from 'node:util';
import { spawn, spawnSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SUBSYSTEM = 'uk.patii.max.window-manager';
const PROJECT_PATH = 'window-manager.xcodeproj';
const SCHEME = 'window-manager';
const DESTINATION = 'platform=macOS';

const { values } = parseArgs({
  options: {
    debug: { type: 'boolean', default: false },
    release: { type: 'boolean', default: false },
    prod: { type: 'boolean', default: false },
    production: { type: 'boolean', default: false },
    log: { type: 'boolean', default: false },
    'no-log': { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
  allowPositionals: false,
});

if (values.help) {
  printHelp();
  process.exit(0);
}

const wantsRelease = Boolean(
  values.release || values.prod || values.production,
);
const configuration = wantsRelease ? 'Release' : 'Debug';

let streamLogs = configuration === 'Debug';
if (values.log) {
  streamLogs = true;
}
if (values['no-log']) {
  streamLogs = false;
}

log(`Building ${configuration}...`);
runOrExit('xcodebuild', [
  '-project',
  PROJECT_PATH,
  '-scheme',
  SCHEME,
  '-configuration',
  configuration,
  '-destination',
  DESTINATION,
  'build',
]);

log('Stopping previous instances (if any)...');
spawnSync('pkill', ['-x', 'window-manager'], {
  stdio: 'ignore',
});

const latestDerivedData = findLatestDerivedData();
if (!latestDerivedData) {
  fail('Could not find DerivedData for window-manager.');
}

const appPath = join(
  latestDerivedData,
  'Build',
  'Products',
  configuration,
  'window-manager.app',
);
log(`Launching: ${appPath}`);
runOrExit('open', [appPath]);

if (streamLogs) {
  log('Streaming logs (Ctrl+C to stop):');
  const child = spawn(
    'log',
    [
      'stream',
      '--style',
      'compact',
      '--type',
      'log',
      '--level',
      'debug',
      '--predicate',
      `subsystem == \"${SUBSYSTEM}\"`,
    ],
    { stdio: 'inherit' },
  );

  child.on('exit', (code) => {
    process.exit(code ?? 0);
  });
} else {
  log('Done.');
}

function runOrExit(command: string, args: string[]): void {
  const result = spawnSync(command, args, { stdio: 'inherit' });
  if (result.error) {
    fail(`Failed to run ${command}: ${result.error.message}`);
  }
  if ((result.status ?? 1) !== 0) {
    fail(`${command} exited with status ${result.status ?? 1}`);
  }
}

function findLatestDerivedData(): string | null {
  const base = join(homedir(), 'Library', 'Developer', 'Xcode', 'DerivedData');

  let dirs: string[];
  try {
    dirs = readdirSync(base)
      .filter((name) => name.startsWith('window-manager-'))
      .map((name) => join(base, name));
  } catch {
    return null;
  }

  if (dirs.length === 0) {
    return null;
  }

  dirs.sort((a, b) => {
    const aTime = statSync(a).mtimeMs;
    const bTime = statSync(b).mtimeMs;
    return bTime - aTime;
  });

  return dirs[0] ?? null;
}

function log(message: string): void {
  console.log(`[run] ${message}`);
}

function fail(message: string): never {
  console.error(`[run] ${message}`);
  process.exit(1);
}

function printHelp() {
  console.log(
    `Usage: ./run.ts [--debug|--release] [--log|--no-log]

Builds, restarts the app, and optionally starts log streaming.

Options:
  --debug                 Build and run Debug (default, logs on)
  --release, --prod       Build and run Release (default logs off)
  --production            Alias for --release
  --log                   Force log streaming on
  --no-log                Force log streaming off
  -h, --help              Show this help
`,
  );
}

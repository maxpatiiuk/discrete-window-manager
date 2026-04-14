import { parseArgs } from 'node:util';
import { spawn, spawnSync } from 'node:child_process';
import { readdirSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SUBSYSTEM = 'uk.patii.max.window-manager';
const PROJECT_PATH = 'window-manager.xcodeproj';
const SCHEME = 'window-manager';
const DESTINATION = 'platform=macOS';
const DEFAULT_STOP_WAIT_MS = 400;

const { values } = parseArgs({
  options: {
    debug: { type: 'boolean', default: false },
    release: { type: 'boolean', default: false },
    prod: { type: 'boolean', default: false },
    production: { type: 'boolean', default: false },
    log: { type: 'boolean', default: false },
    'no-log': { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
    'stop-wait-ms': { type: 'string' },
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

const stopWaitMs = parseStopWaitMs(values['stop-wait-ms']);

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
waitForProcessExit('window-manager', stopWaitMs);

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
launchAppOrExit(appPath);

if (streamLogs) {
  log('Streaming logs (Ctrl+C to stop):');
  const child = spawn(
    'log',
    [
      'stream',
      '--style',
      'compact',
      '--color',
      'always',
      '--type',
      'log',
      '--level',
      'debug',
      '--predicate',
      `subsystem == \"${SUBSYSTEM}\"`,
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );

  child.stdout?.setEncoding('utf8');
  child.stderr?.setEncoding('utf8');

  pipeLogStream(child.stdout, process.stdout);
  pipeLogStream(child.stderr, process.stderr);

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

function launchAppOrExit(appPath: string): void {
  const maxAttempts = 6;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const result = spawnSync('open', [appPath], {
      encoding: 'utf-8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    if ((result.status ?? 1) === 0) {
      return;
    }

    if (isProcessRunning('window-manager')) {
      log('App is already running after launch attempt; continuing.');
      return;
    }

    const stderr = (result.stderr ?? '').trim();
    const canRetry = attempt < maxAttempts;

    if (!canRetry) {
      if (stderr.length > 0) {
        console.error(stderr);
      }
      fail(`open exited with status ${result.status ?? 1}`);
    }

    log(`Launch attempt ${attempt} failed; retrying...`);
    sleepMs(250);
  }
}

function waitForProcessExit(processName: string, timeoutMs: number): void {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    if (!isProcessRunning(processName)) {
      return;
    }
    sleepMs(100);
  }
}

function isProcessRunning(processName: string): boolean {
  const result = spawnSync('pgrep', ['-x', processName], {
    stdio: 'ignore',
  });
  return (result.status ?? 1) === 0;
}

function sleepMs(ms: number): void {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
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
  --stop-wait-ms <ms>     Wait timeout after pkill (default ${DEFAULT_STOP_WAIT_MS})
  -h, --help              Show this help
`,
  );
}

function parseStopWaitMs(raw: string | undefined): number {
  const envValue = process.env.WM_STOP_WAIT_MS;
  const source = raw ?? envValue;

  if (source === undefined) {
    return DEFAULT_STOP_WAIT_MS;
  }

  const parsed = Number.parseInt(source, 10);
  if (!Number.isFinite(parsed) || parsed < 0) {
    fail(`Invalid stop wait value: ${source}`);
  }

  return parsed;
}

function pipeLogStream(
  source: NodeJS.ReadableStream | null | undefined,
  target: NodeJS.WriteStream,
): void {
  if (!source) {
    return;
  }

  let buffered = '';
  source.on('data', (chunk: string | Buffer) => {
    buffered += chunk.toString();

    const lines = buffered.split('\n');
    buffered = lines.pop() ?? '';

    for (const line of lines) {
      target.write(`${compactLogLine(line)}\n`);
    }
  });

  source.on('end', () => {
    if (buffered.length > 0) {
      target.write(`${compactLogLine(buffered)}\n`);
    }
  });
}

function compactLogLine(line: string): string {
  const stripped = line.replace(/\r$/, '');

  const match = stripped.match(
    /^\d{4}-\d{2}-\d{2}\s+(\d{2}:\d{2}:\d{2}\.\d+)\s+\S+\s+\S+\[[^\]]+\]\s+\[[^:]+:(.*)$/,
  );
  if (match) {
    const time = match[1];
    const remainder = match[2];
    return `${time} ${remainder}`;
  }

  return stripped.replace(/^\d{4}-\d{2}-\d{2}\s+/, '');
}

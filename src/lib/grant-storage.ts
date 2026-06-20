import crypto from "crypto";
import { promises as fs } from "fs";
import path from "path";
import { getGoogleDriveAuthMode } from "./google-drive-config";
import {
  readTextFileFromGoogleDrive,
  writeTextFileToGoogleDrive,
} from "./google-drive-storage";

type GrantJsonStorageOptions<T> = {
  envName: string;
  defaultRelativePath: string;
  label: string;
  backendEnvNames?: readonly string[];
  defaultBackend?: string;
  localReadOnlyMessage?: string;
  googleDriveBackup?: {
    enabledEnvName: string;
    fileNameEnvName?: string;
    fileIdEnvName?: string;
    defaultFileName: string;
  };
  emptyData: () => T;
  normalize: (value: unknown) => T;
};

type GrantStorageErrorDetails = {
  label: string;
  operation: string;
  path: string;
  backend?: string;
  code?: string;
  message: string;
  cause?: string;
  backupPath?: string;
  runtime?: string;
};

type GrantStorageBackupStatus = {
  enabled: boolean;
  backend?: "google-drive";
  path?: string;
  message?: string;
};

export class GrantStorageError extends Error {
  readonly details: GrantStorageErrorDetails;

  constructor(message: string, details: GrantStorageErrorDetails) {
    super(message);
    this.name = "GrantStorageError";
    this.details = details;
  }
}

export function resolveGrantStoragePath(envName: string, defaultRelativePath: string) {
  const configuredPath = process.env[envName]?.trim();
  return path.resolve(
    /* turbopackIgnore: true */ process.cwd(),
    configuredPath || defaultRelativePath,
  );
}

const defaultGrantStorageBackendEnvNames = ["GRANT_STORAGE_BACKEND", "REPORT_STORAGE_BACKEND"] as const;

function grantStorageBackend(options: Pick<GrantJsonStorageOptions<unknown>, "backendEnvNames" | "defaultBackend"> = {}) {
  const backendEnvNames = options.backendEnvNames ?? defaultGrantStorageBackendEnvNames;

  for (const envName of backendEnvNames) {
    const backend = process.env[envName]?.trim();
    if (backend) return backend.toLowerCase();
  }

  return (options.defaultBackend ?? "local-json").toLowerCase();
}

function isGoogleDriveGrantStorage(options: GrantJsonStorageOptions<unknown>) {
  return grantStorageBackend(options) === "google-drive";
}

function isGoogleDriveBackupEnabled(options: GrantJsonStorageOptions<unknown>) {
  const envName = options.googleDriveBackup?.enabledEnvName;
  if (!envName) return false;

  const value = process.env[envName]?.trim().toLowerCase() ?? "";
  return ["1", "true", "yes", "on", "google-drive"].includes(value);
}

function googleDriveBackupFileName(options: GrantJsonStorageOptions<unknown>) {
  const configured = options.googleDriveBackup?.fileNameEnvName
    ? process.env[options.googleDriveBackup.fileNameEnvName]?.trim()
    : "";
  return configured || options.googleDriveBackup?.defaultFileName || "";
}

function googleDriveBackupFileId(options: GrantJsonStorageOptions<unknown>) {
  return options.googleDriveBackup?.fileIdEnvName
    ? process.env[options.googleDriveBackup.fileIdEnvName]?.trim() ?? ""
    : "";
}

function googleDriveBackupStatus(options: GrantJsonStorageOptions<unknown>): GrantStorageBackupStatus | undefined {
  if (!options.googleDriveBackup) return undefined;
  if (!isGoogleDriveBackupEnabled(options)) return { enabled: false };

  const fileName = googleDriveBackupFileName(options);
  return {
    enabled: true,
    backend: "google-drive",
    path: fileName ? `google-drive:${fileName}` : undefined,
    message:
      "Primary storage remains local JSON. Google Drive is used only as a backup mirror after successful local writes.",
  };
}

function grantDriveFileName(envName: string, defaultRelativePath: string) {
  const explicit = process.env[`${envName}_DRIVE_FILENAME`]?.trim();
  if (explicit) return explicit;

  const configuredPath = process.env[envName]?.trim();
  return path.basename(configuredPath || defaultRelativePath);
}

function grantDriveFileId(envName: string) {
  return process.env[`${envName}_DRIVE_FILE_ID`]?.trim() ?? "";
}

function isServerlessReadOnlyPath(targetPath: string) {
  return Boolean(
    process.env.VERCEL ||
      process.env.AWS_LAMBDA_FUNCTION_NAME ||
      targetPath === "/var/task" ||
      targetPath.startsWith("/var/task/"),
  );
}

function runtimeLabel() {
  if (process.env.VERCEL) return "vercel";
  if (process.env.AWS_LAMBDA_FUNCTION_NAME) return "aws-lambda";
  return "node";
}

export function grantStorageErrorDetails(error: unknown) {
  if (error instanceof GrantStorageError) return error.details;
  if (error instanceof Error) return { message: error.message };
  return { message: String(error) };
}

export function createGrantJsonStorage<T>(options: GrantJsonStorageOptions<T>) {
  const filePath = () => resolveGrantStoragePath(options.envName, options.defaultRelativePath);
  const driveFileName = () => grantDriveFileName(options.envName, options.defaultRelativePath);
  const driveFileId = () => grantDriveFileId(options.envName);

  return {
    path: filePath,
    writeReadiness() {
      const backend = grantStorageBackend(options);
      const storagePath = backend === "google-drive" ? `google-drive:${driveFileName()}` : filePath();
      const runtime = runtimeLabel();

      if (backend !== "google-drive" && isServerlessReadOnlyPath(storagePath)) {
        return {
          writable: false,
          backend,
          path: storagePath,
          runtime,
          details: {
            label: options.label,
            operation: "write",
            path: storagePath,
            backend,
            code: "SERVERLESS_LOCAL_STORAGE",
            runtime,
            message: options.localReadOnlyMessage ??
              "Local JSON grant storage cannot write under /var/task. Set REPORT_STORAGE_BACKEND=google-drive or GRANT_STORAGE_BACKEND=google-drive in Vercel.",
          },
        };
      }

      return {
        writable: true,
        backend,
        path: storagePath,
        runtime,
        backup: googleDriveBackupStatus(options),
        details: undefined,
      };
    },
    async read() {
      if (isGoogleDriveGrantStorage(options)) {
        const raw = await readGoogleDriveData(options.label, driveFileName(), driveFileId());
        if (!raw) return options.emptyData();
        return parseStoredJson(raw, options, async (error) => {
          await writeTextFileFromGoogleDriveBackup(driveFileName(), raw, error);
        });
      }

      const targetPath = filePath();
      let raw: string;

      try {
        raw = await fs.readFile(targetPath, "utf8");
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") return options.emptyData();
        throw storageError(error, options.label, "read", targetPath, {}, options);
      }

      return parseStoredJson(raw, options, (error) => moveCorruptJsonAside(options.label, targetPath, error, options));
    },
    async write(data: T) {
      if (isGoogleDriveGrantStorage(options)) {
        await writeGoogleDriveData(options.label, driveFileName(), JSON.stringify(data, null, 2), driveFileId());
        return;
      }

      const targetPath = filePath();
      const temporaryPath = `${targetPath}.${process.pid}.${Date.now()}.${crypto.randomUUID()}.tmp`;

      if (isServerlessReadOnlyPath(targetPath)) {
        throw new GrantStorageError(`${options.label} storage write failed.`, {
          label: options.label,
          operation: "write",
          path: targetPath,
          backend: grantStorageBackend(options),
          code: "SERVERLESS_LOCAL_STORAGE",
          runtime: runtimeLabel(),
          message: options.localReadOnlyMessage ??
            "Local JSON grant storage cannot write under /var/task. Set REPORT_STORAGE_BACKEND=google-drive or GRANT_STORAGE_BACKEND=google-drive in Vercel.",
        });
      }

      try {
        await fs.mkdir(path.dirname(targetPath), { recursive: true });
        await fs.writeFile(temporaryPath, JSON.stringify(data, null, 2), "utf8");
        await fs.rename(temporaryPath, targetPath);
      } catch (error) {
        await fs.unlink(temporaryPath).catch(() => undefined);
        throw storageError(error, options.label, "write", targetPath, {}, options);
      }

      await mirrorLocalJsonToGoogleDrive(options, data).catch((error) => {
        console.warn(`${options.label} Google Drive backup mirror failed`, {
          details: grantStorageErrorDetails(error),
        });
      });
    },
    async backupNow() {
      const data = await this.read();
      return mirrorLocalJsonToGoogleDrive(options, data, { required: true });
    },
  };
}

async function parseStoredJson<T>(
  raw: string,
  options: GrantJsonStorageOptions<T>,
  backupCorrupt: (error: SyntaxError) => Promise<void>,
) {
  try {
    return options.normalize(JSON.parse(raw));
  } catch (error) {
    if (!(error instanceof SyntaxError)) {
      throw storageError(error, options.label, "normalize", storageLocation(options), {}, options);
    }

    await backupCorrupt(error);
    return options.emptyData();
  }
}

function storageLocation(options: GrantJsonStorageOptions<unknown>) {
  return isGoogleDriveGrantStorage(options)
    ? `google-drive:${grantDriveFileName(options.envName, options.defaultRelativePath)}`
    : resolveGrantStoragePath(options.envName, options.defaultRelativePath);
}

async function readGoogleDriveData(label: string, fileName: string, fileId: string) {
  ensureGoogleDriveGrantStorageConfigured(label, fileName);
  try {
    return await readTextFileFromGoogleDrive(fileName, fileId);
  } catch (error) {
    throw storageError(error, label, "read", `google-drive:${fileName}`, { backend: "google-drive" });
  }
}

async function writeGoogleDriveData(label: string, fileName: string, contents: string, fileId: string) {
  ensureGoogleDriveGrantStorageConfigured(label, fileName);
  try {
    await writeTextFileToGoogleDrive(fileName, contents, fileId);
  } catch (error) {
    throw storageError(error, label, "write", `google-drive:${fileName}`, { backend: "google-drive" });
  }
}

async function writeTextFileFromGoogleDriveBackup(fileName: string, raw: string, parseError: SyntaxError) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  await writeTextFileToGoogleDrive(`${fileName}.corrupt-${stamp}`, raw).catch((error) => {
    throw storageError(error, "grant google drive", "backup-corrupt-json", `google-drive:${fileName}`, {
      backend: "google-drive",
      cause: parseError.message,
      backupPath: `google-drive:${fileName}.corrupt-${stamp}`,
    });
  });
}

function ensureGoogleDriveGrantStorageConfigured(label: string, fileName: string) {
  if (getGoogleDriveAuthMode()) return;
  throw new GrantStorageError(`${label} storage Google Drive configuration is incomplete.`, {
    label,
    operation: "configure",
    path: `google-drive:${fileName}`,
    backend: "google-drive",
    code: "GOOGLE_DRIVE_NOT_CONFIGURED",
    message:
      "Grant storage is set to google-drive, but Google Drive credentials are incomplete. Set GOOGLE_DRIVE_CLIENT_ID, GOOGLE_DRIVE_CLIENT_SECRET, and GOOGLE_DRIVE_REFRESH_TOKEN.",
  });
}

async function moveCorruptJsonAside(
  label: string,
  targetPath: string,
  parseError: SyntaxError,
  options: GrantJsonStorageOptions<unknown>,
) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = `${targetPath}.corrupt-${stamp}`;

  try {
    await fs.rename(targetPath, backupPath);
  } catch (error) {
    throw storageError(error, label, "backup-corrupt-json", targetPath, {
      cause: parseError.message,
      backupPath,
    }, options);
  }
}

async function mirrorLocalJsonToGoogleDrive<T>(
  options: GrantJsonStorageOptions<T>,
  data: T,
  mirrorOptions: { required?: boolean } = {},
) {
  if (!options.googleDriveBackup || !isGoogleDriveBackupEnabled(options)) {
    if (mirrorOptions.required) {
      throw new GrantStorageError(`${options.label} Google Drive backup is not enabled.`, {
        label: options.label,
        operation: "backup",
        path: storageLocation(options),
        backend: grantStorageBackend(options),
        code: "GOOGLE_DRIVE_BACKUP_DISABLED",
        message: `Set ${options.googleDriveBackup?.enabledEnvName ?? "the backup env"}=true to enable Google Drive backup mirroring.`,
      });
    }

    return { ok: false, skipped: true, reason: "disabled" as const };
  }

  const fileName = googleDriveBackupFileName(options);
  const fileId = googleDriveBackupFileId(options);
  if (!fileName) {
    throw new GrantStorageError(`${options.label} Google Drive backup filename is missing.`, {
      label: options.label,
      operation: "backup",
      path: "google-drive:",
      backend: "google-drive",
      code: "GOOGLE_DRIVE_BACKUP_FILENAME_MISSING",
      message: "Set a Google Drive backup filename or defaultFileName.",
    });
  }

  await writeGoogleDriveData(options.label, fileName, JSON.stringify(data, null, 2), fileId);
  return { ok: true, backend: "google-drive" as const, path: `google-drive:${fileName}` };
}

function storageError(
  error: unknown,
  label: string,
  operation: string,
  targetPath: string,
  extra: Partial<GrantStorageErrorDetails> = {},
  options?: Pick<GrantJsonStorageOptions<unknown>, "backendEnvNames" | "defaultBackend">,
) {
  if (error instanceof GrantStorageError) return error;
  const nodeError = error as NodeJS.ErrnoException;
  const message = error instanceof Error ? error.message : String(error);

  return new GrantStorageError(`${label} storage ${operation} failed.`, {
    label,
    operation,
    path: targetPath,
    backend: grantStorageBackend(options),
    code: nodeError.code,
    message,
    ...extra,
  });
}

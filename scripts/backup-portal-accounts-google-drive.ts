import { backupPortalAccountStorageToGoogleDrive } from "../src/lib/portal-accounts";

async function main() {
  const result = await backupPortalAccountStorageToGoogleDrive();
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});

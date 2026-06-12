import { NextResponse } from "next/server";

import { getWiregeneAppMode } from "@/lib/app-mode";
import { grantStorageErrorDetails } from "@/lib/grant-storage";
import {
  listPortalAccountSummaries,
  portalAccountStorageWriteReadiness,
} from "@/lib/portal-accounts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (getWiregeneAppMode(request.headers.get("host")) !== "portal") {
    return notFound();
  }

  if (!isAuthorizedHealthRequest(request)) {
    return notFound();
  }

  const readiness = portalAccountStorageWriteReadiness();

  try {
    const accounts = await listPortalAccountSummaries();
    return NextResponse.json(
      {
        ok: true,
        accountCount: accounts.length,
        storage: readiness,
      },
      {
        headers: {
          "Cache-Control": "no-store",
        },
      },
    );
  } catch (error) {
    console.error("[api/admin/storage-health] portal account storage health failed", {
      details: grantStorageErrorDetails(error),
    });

    return NextResponse.json(
      {
        ok: false,
        storage: readiness,
        error: grantStorageErrorDetails(error),
      },
      {
        status: 500,
        headers: {
          "Cache-Control": "no-store",
        },
      },
    );
  }
}

function isAuthorizedHealthRequest(request: Request) {
  const secret = process.env.PORTAL_STORAGE_HEALTH_SECRET?.trim();
  if (!secret) return false;

  const provided = request.headers.get("x-wiregene-storage-health-secret")?.trim() ?? "";
  return provided === secret;
}

function notFound() {
  return new NextResponse("Not found.", { status: 404 });
}

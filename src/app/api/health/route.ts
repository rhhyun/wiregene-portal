import { NextResponse } from "next/server";
import { BRIEFING_VERSION } from "@/lib/version";

export function GET() {
  return NextResponse.json({
    ok: true,
    app: "wiregene-portal",
    version: BRIEFING_VERSION,
    timestamp: new Date().toISOString(),
  });
}

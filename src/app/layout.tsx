import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Wiregene Portal",
  description: "Wiregene account management and site launcher portal.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko" className="antialiased">
      <body>{children}</body>
    </html>
  );
}

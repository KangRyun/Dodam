import type { Metadata } from "next";

import { AppProviders } from "@/app/providers";

import "./globals.css";

export const metadata: Metadata = {
  title: "도담",
  description: "보호자와 전문가가 함께하는 도담 커뮤니티",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ko">
      <body>
        <AppProviders>{children}</AppProviders>
      </body>
    </html>
  );
}

import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Gather — Event hosting made simple",
  description: "Create events, manage RSVPs, and keep your guests informed.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

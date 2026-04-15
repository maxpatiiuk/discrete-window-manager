import { resolve } from "node:path";
import { defineConfig } from "vite";

// Bundle to a single file that Phoenix can execute directly.
export default defineConfig({
  build: {
    lib: {
      entry: "src/index.ts",
      formats: ["iife"],
      name: "PhoenixConfig",
      fileName: () => "phoenix.js",
    },
  },
});

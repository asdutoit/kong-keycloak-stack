import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { keycloakify } from "keycloakify/vite-plugin";

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [
        react(),
        keycloakify({
            // Additive theme name — coexists with the existing `tennet` /
            // `keycloak` themes; nothing else is overridden. Scope it to a
            // realm or, better, to just the api-onboarding client via the
            // client's loginTheme override.
            themeName: "api-portal",
            accountThemeImplementation: "none"
        })
    ]
});

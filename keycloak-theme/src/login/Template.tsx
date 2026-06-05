import { useEffect } from "react";
import type { TemplateProps } from "keycloakify/login/TemplateProps";
import { useInitialize } from "keycloakify/login/Template.useInitialize";
import type { KcContext } from "./KcContext";
import type { I18n } from "./i18n";
import "./main.css";

// Bespoke pass-through Template. Each page (e.g. Login) renders the full
// `.lp` two-panel shell itself, so the Template only needs to run
// useInitialize (loads Keycloak's required client resources / scripts)
// and then render the page. We deliberately drop the default PatternFly
// card chrome — doUseDefaultCss is false from KcPage.
export default function Template(props: TemplateProps<KcContext, I18n>) {
    const { kcContext, doUseDefaultCss, children } = props;

    useEffect(() => {
        document.title = "Sign in · API Onboarding Portal";
    }, []);

    const { isReadyToRender } = useInitialize({ kcContext, doUseDefaultCss });

    if (!isReadyToRender) {
        return null;
    }

    return <>{children}</>;
}

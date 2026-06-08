import { kcSanitize } from "keycloakify/lib/kcSanitize";
import type { PageProps } from "keycloakify/login/pages/PageProps";
import type { KcContext } from "../KcContext";
import type { I18n } from "../i18n";
import { BrandPanel } from "../BrandPanel";

// Forgot-password page (login-reset-password.ftl), restyled to the portal's
// two-panel .lp design to match Login/Register. LEFT = the email/username
// form that posts to url.loginAction (Keycloak emails a reset link); RIGHT =
// the shared branded panel.
export default function LoginResetPassword(props: PageProps<Extract<KcContext, { pageId: "login-reset-password.ftl" }>, I18n>) {
    const { kcContext, i18n, Template, doUseDefaultCss, classes } = props;
    const { url, realm, auth, messagesPerField, message } = kcContext;
    const { msg, msgStr } = i18n;

    const hasError = messagesPerField.existsError("username");

    return (
        <Template kcContext={kcContext} i18n={i18n} doUseDefaultCss={doUseDefaultCss} classes={classes} displayMessage={false} headerNode={null}>
            <div className="lp" data-theme="dark">
                <div className="bg-grid" />
                <div className="lp-split">
                    {/* ---------------------------------------------- LEFT */}
                    <div className="lp-pane-left">
                        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                            <BackButton />
                            <PortalMark />
                        </div>

                        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", maxWidth: 420 }}>
                            <h1 style={{ fontSize: 36, lineHeight: 1.1, letterSpacing: "-0.025em", fontWeight: 500, margin: 0, color: "var(--ink-100)" }}>
                                Reset your{" "}
                                <span style={{ fontStyle: "italic", fontWeight: 400, fontFamily: "'IBM Plex Serif', serif", color: "var(--orange-500)" }}>
                                    password
                                </span>
                                .
                            </h1>
                            <p style={{ marginTop: 14, fontSize: 15, lineHeight: 1.55, color: "var(--ink-300)", marginBottom: 32 }}>
                                Enter your {realm.loginWithEmailAllowed ? "email" : "username"} and we&apos;ll send you a link to set a new password.
                            </p>

                            {message !== undefined && (
                                <div
                                    className={`lp-banner ${message.type}`}
                                    dangerouslySetInnerHTML={{ __html: kcSanitize(message.summary) }}
                                />
                            )}

                            <form id="kc-reset-password-form" action={url.loginAction} method="post">
                                <div className="lp-field">
                                    <label htmlFor="username" className="lp-label">
                                        {!realm.loginWithEmailAllowed
                                            ? msg("username")
                                            : !realm.registrationEmailAsUsername
                                              ? msg("usernameOrEmail")
                                              : msg("email")}
                                    </label>
                                    <div className="lp-input-wrap">
                                        <input
                                            id="username"
                                            name="username"
                                            className="lp-input"
                                            type="text"
                                            autoFocus
                                            autoComplete="username"
                                            defaultValue={auth.attemptedUsername ?? ""}
                                            aria-invalid={hasError}
                                        />
                                    </div>
                                </div>

                                {hasError && (
                                    <div
                                        className="lp-field-error"
                                        aria-live="polite"
                                        style={{ marginTop: -6, marginBottom: 16 }}
                                        dangerouslySetInnerHTML={{ __html: kcSanitize(messagesPerField.get("username")) }}
                                    />
                                )}

                                <button className="btn btn-primary btn-lg" type="submit" style={{ width: "100%", marginTop: 8 }}>
                                    {msgStr("doSubmit")} →
                                </button>
                            </form>

                            <p style={{ marginTop: 24, fontSize: 13, color: "var(--ink-300)", textAlign: "center" }}>
                                <a href={url.loginUrl} style={{ color: "var(--orange-500)", textDecoration: "none", fontWeight: 500 }}>
                                    {msg("backToLogin")}
                                </a>
                            </p>
                        </div>

                        <div
                            style={{
                                paddingTop: 24,
                                fontSize: 12,
                                color: "var(--ink-400)",
                                display: "flex",
                                justifyContent: "space-between",
                                fontFamily: "var(--font-portal-mono)",
                                letterSpacing: "0.04em"
                            }}
                        >
                            <span>KEYCLOAK SSO · OIDC</span>
                            <span>API ONBOARDING</span>
                        </div>
                    </div>

                    {/* --------------------------------------------- RIGHT */}
                    <BrandPanel />
                </div>
            </div>
        </Template>
    );
}

function PortalMark() {
    return (
        <span
            style={{
                fontFamily: "var(--font-portal-mono)",
                fontSize: 12,
                fontWeight: 500,
                letterSpacing: "0.02em",
                color: "var(--ink-200)",
                textTransform: "uppercase"
            }}
        >
            <span style={{ color: "var(--orange-500)", marginRight: 6 }}>◆</span>
            API Onboarding
        </span>
    );
}

// Top-left "← Back" — returns to the login page the user came from.
function BackButton() {
    return (
        <button
            type="button"
            onClick={() => window.history.back()}
            style={{
                fontFamily: "var(--font-portal-mono)",
                fontSize: 11,
                letterSpacing: "0.06em",
                textTransform: "uppercase",
                color: "var(--ink-400)",
                background: "transparent",
                border: "none",
                padding: 0,
                cursor: "pointer"
            }}
        >
            ← Back
        </button>
    );
}

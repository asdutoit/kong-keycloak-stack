import { kcSanitize } from "keycloakify/lib/kcSanitize";
import { useIsPasswordRevealed } from "keycloakify/tools/useIsPasswordRevealed";
import type { PageProps } from "keycloakify/login/pages/PageProps";
import type { KcContext } from "../KcContext";
import type { I18n } from "../i18n";
import { BrandPanel } from "../BrandPanel";

// Set-new-password page (login-update-password.ftl), restyled to the portal's
// two-panel .lp design. Reached from the reset email link (and any
// UPDATE_PASSWORD required action). Posts the new password to url.loginAction.
export default function LoginUpdatePassword(props: PageProps<Extract<KcContext, { pageId: "login-update-password.ftl" }>, I18n>) {
    const { kcContext, i18n, Template, doUseDefaultCss, classes } = props;
    const { url, messagesPerField, isAppInitiatedAction, message } = kcContext;
    const { msg, msgStr } = i18n;

    const hasError = messagesPerField.existsError("password", "password-confirm");

    return (
        <Template kcContext={kcContext} i18n={i18n} doUseDefaultCss={doUseDefaultCss} classes={classes} displayMessage={false} headerNode={null}>
            <div className="lp" data-theme="dark">
                <div className="bg-grid" />
                <div className="lp-split">
                    {/* ---------------------------------------------- LEFT */}
                    <div className="lp-pane-left">
                        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                            <span
                                style={{
                                    fontFamily: "var(--font-portal-mono)",
                                    fontSize: 11,
                                    letterSpacing: "0.06em",
                                    textTransform: "uppercase",
                                    color: "var(--ink-400)"
                                }}
                            >
                                API Onboarding Portal
                            </span>
                            <PortalMark />
                        </div>

                        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", maxWidth: 420 }}>
                            <h1 style={{ fontSize: 36, lineHeight: 1.1, letterSpacing: "-0.025em", fontWeight: 500, margin: 0, color: "var(--ink-100)" }}>
                                Choose a new{" "}
                                <span style={{ fontStyle: "italic", fontWeight: 400, fontFamily: "'IBM Plex Serif', serif", color: "var(--orange-500)" }}>
                                    password
                                </span>
                                .
                            </h1>
                            <p style={{ marginTop: 14, fontSize: 15, lineHeight: 1.55, color: "var(--ink-300)", marginBottom: 32 }}>
                                Pick a strong password you don&apos;t use anywhere else.
                            </p>

                            {message !== undefined && (
                                <div
                                    className={`lp-banner ${message.type}`}
                                    dangerouslySetInnerHTML={{ __html: kcSanitize(message.summary) }}
                                />
                            )}

                            <form id="kc-passwd-update-form" action={url.loginAction} method="post">
                                <div className="lp-field">
                                    <label htmlFor="password-new" className="lp-label">
                                        {msg("passwordNew")}
                                    </label>
                                    <PasswordInput id="password-new" autoComplete="new-password" i18n={i18n} hasError={hasError} />
                                </div>

                                <div className="lp-field">
                                    <label htmlFor="password-confirm" className="lp-label">
                                        {msg("passwordConfirm")}
                                    </label>
                                    <PasswordInput id="password-confirm" autoComplete="new-password" i18n={i18n} hasError={hasError} />
                                </div>

                                {hasError && (
                                    <div
                                        className="lp-field-error"
                                        aria-live="polite"
                                        style={{ marginTop: -6, marginBottom: 16 }}
                                        dangerouslySetInnerHTML={{ __html: kcSanitize(messagesPerField.getFirstError("password", "password-confirm")) }}
                                    />
                                )}

                                <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13, color: "var(--ink-300)", marginBottom: 24 }}>
                                    <input type="checkbox" id="logout-sessions" name="logout-sessions" value="on" defaultChecked />
                                    {msg("logoutOtherSessions")}
                                </label>

                                <button className="btn btn-primary btn-lg" type="submit" style={{ width: "100%" }}>
                                    {msgStr("doSubmit")} →
                                </button>

                                {isAppInitiatedAction && (
                                    <button
                                        className="btn btn-ghost btn-lg"
                                        type="submit"
                                        name="cancel-aia"
                                        value="true"
                                        style={{ width: "100%", marginTop: 10 }}
                                    >
                                        {msgStr("doCancel")}
                                    </button>
                                )}
                            </form>
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

function PasswordInput(props: { id: string; autoComplete: string; i18n: I18n; hasError: boolean }) {
    const { id, autoComplete, i18n, hasError } = props;
    const { msgStr } = i18n;
    const { isPasswordRevealed, toggleIsPasswordRevealed } = useIsPasswordRevealed({ passwordInputId: id });

    return (
        <div className="lp-input-wrap">
            <input
                id={id}
                className="lp-input"
                name={id}
                type={isPasswordRevealed ? "text" : "password"}
                autoComplete={autoComplete}
                aria-invalid={hasError}
                style={{ paddingRight: 64 }}
            />
            <button
                type="button"
                className="lp-reveal"
                aria-label={msgStr(isPasswordRevealed ? "hidePassword" : "showPassword")}
                aria-controls={id}
                onClick={toggleIsPasswordRevealed}
            >
                {isPasswordRevealed ? "Hide" : "Show"}
            </button>
        </div>
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

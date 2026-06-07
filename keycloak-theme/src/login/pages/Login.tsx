import { useState } from "react";
import { kcSanitize } from "keycloakify/lib/kcSanitize";
import { useIsPasswordRevealed } from "keycloakify/tools/useIsPasswordRevealed";
import type { PageProps } from "keycloakify/login/pages/PageProps";
import type { KcContext } from "../KcContext";
import type { I18n } from "../i18n";
import { BrandPanel } from "../BrandPanel";

// Login page (login.ftl) restyled to match the portal's /signin design:
// a two-panel layout. LEFT = the real Keycloak username/password form.
// RIGHT = the branded marketing panel (code sample + stats). The form
// posts to url.loginAction exactly like the default page; only the
// presentation changes. Conditionals (rememberMe / forgot / register /
// social) are preserved so the theme still works if those realm features
// are enabled later.
export default function Login(props: PageProps<Extract<KcContext, { pageId: "login.ftl" }>, I18n>) {
    const { kcContext, i18n, Template, doUseDefaultCss, classes } = props;
    const { social, realm, url, usernameHidden, login, auth, registrationDisabled, messagesPerField, message } = kcContext;
    const { msg, msgStr } = i18n;

    const [isLoginButtonDisabled, setIsLoginButtonDisabled] = useState(false);
    const hasError = messagesPerField.existsError("username", "password");

    return (
        <Template kcContext={kcContext} i18n={i18n} doUseDefaultCss={doUseDefaultCss} classes={classes} displayMessage={false} headerNode={null}>
            <div className="lp" data-theme="dark">
                <div className="bg-grid" />
                <div className="lp-split">
                    {/* ---------------------------------------------- LEFT */}
                    <div className="lp-pane-left">
                        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                            <a
                                href={url.loginUrl}
                                style={{
                                    fontFamily: "var(--font-portal-mono)",
                                    fontSize: 11,
                                    letterSpacing: "0.06em",
                                    textTransform: "uppercase",
                                    color: "var(--ink-400)",
                                    textDecoration: "none"
                                }}
                            >
                                {realm.displayNameHtml ? realm.displayName : "API Onboarding Portal"}
                            </a>
                            <PortalMark />
                        </div>

                        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", maxWidth: 420 }}>
                            <h1 style={{ fontSize: 36, lineHeight: 1.1, letterSpacing: "-0.025em", fontWeight: 500, margin: 0, color: "var(--ink-100)" }}>
                                Welcome{" "}
                                <span style={{ fontStyle: "italic", fontWeight: 400, fontFamily: "'IBM Plex Serif', serif", color: "var(--orange-500)" }}>
                                    back
                                </span>
                                .
                            </h1>
                            <p style={{ marginTop: 14, fontSize: 15, lineHeight: 1.55, color: "var(--ink-300)", marginBottom: 32 }}>
                                Sign in to onboard APIs, manage versions, and your gateway credentials.
                            </p>

                            {/* Global (non-field) message banner */}
                            {message !== undefined && (
                                <div
                                    className={`lp-banner ${message.type}`}
                                    dangerouslySetInnerHTML={{ __html: kcSanitize(message.summary) }}
                                />
                            )}

                            {/* Social / IdP providers — only render if the realm has any.
                                NOTE: intentionally NOT gated by usernameHidden, so a user
                                stuck in password-only / re-auth mode can still retry the
                                AD/ADFS broker instead of being trapped on the password form. */}
                            {realm.password && social?.providers !== undefined && social.providers.length !== 0 && (
                                <div style={{ display: "flex", flexDirection: "column", gap: 10, marginBottom: 22 }}>
                                    {social.providers.map(p => (
                                        <a key={p.alias} href={p.loginUrl} className="btn btn-ghost btn-lg" style={{ width: "100%" }}>
                                            <span dangerouslySetInnerHTML={{ __html: kcSanitize(`Continue with ${p.displayName}`) }} />
                                        </a>
                                    ))}
                                </div>
                            )}

                            {realm.password && (
                                <form
                                    id="kc-form-login"
                                    onSubmit={() => {
                                        setIsLoginButtonDisabled(true);
                                        return true;
                                    }}
                                    action={url.loginAction}
                                    method="post"
                                >
                                    {!usernameHidden && (
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
                                                    tabIndex={2}
                                                    id="username"
                                                    className="lp-input"
                                                    name="username"
                                                    defaultValue={login.username ?? ""}
                                                    type="text"
                                                    autoFocus
                                                    autoComplete="username"
                                                    aria-invalid={hasError}
                                                />
                                            </div>
                                        </div>
                                    )}

                                    {/* Password-only / re-auth escape: when Keycloak re-renders
                                        login.ftl with usernameHidden=true (e.g. after a failed
                                        AD/ADFS broker login) the username field is gone. Without an
                                        escape the user is stuck on a lone password field. Show the
                                        attempted username (if any) read-only and a link back to the
                                        full login page so they can use a different account. */}
                                    {usernameHidden && (
                                        <div className="lp-field">
                                            {auth?.attemptedUsername !== undefined && (
                                                <div style={{ fontSize: 13, color: "var(--ink-300)", marginBottom: 8 }}>
                                                    {auth.attemptedUsername}
                                                </div>
                                            )}
                                            <a
                                                href={url.loginRestartFlowUrl ?? url.loginUrl}
                                                title={msgStr("restartLoginTooltip")}
                                                style={{ color: "var(--orange-500)", fontSize: 13, textDecoration: "none", fontWeight: 500 }}
                                            >
                                                Use a different account
                                            </a>
                                        </div>
                                    )}

                                    <div className="lp-field">
                                        <label htmlFor="password" className="lp-label">
                                            {msg("password")}
                                        </label>
                                        <PasswordInput i18n={i18n} hasError={hasError} />
                                    </div>

                                    {hasError && (
                                        <div
                                            className="lp-field-error"
                                            aria-live="polite"
                                            style={{ marginTop: -6, marginBottom: 16 }}
                                            dangerouslySetInnerHTML={{ __html: kcSanitize(messagesPerField.getFirstError("username", "password")) }}
                                        />
                                    )}

                                    {(realm.rememberMe && !usernameHidden) || realm.resetPasswordAllowed ? (
                                        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }}>
                                            {realm.rememberMe && !usernameHidden ? (
                                                <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13, color: "var(--ink-300)" }}>
                                                    <input tabIndex={5} id="rememberMe" name="rememberMe" type="checkbox" defaultChecked={!!login.rememberMe} />
                                                    {msg("rememberMe")}
                                                </label>
                                            ) : (
                                                <span />
                                            )}
                                            {realm.resetPasswordAllowed && (
                                                <a tabIndex={6} href={url.loginResetCredentialsUrl} style={{ color: "var(--orange-500)", fontSize: 13, textDecoration: "none" }}>
                                                    {msg("doForgotPassword")}
                                                </a>
                                            )}
                                        </div>
                                    ) : (
                                        <div style={{ height: 6 }} />
                                    )}

                                    <input type="hidden" id="id-hidden-input" name="credentialId" value={auth.selectedCredential} />
                                    <button
                                        tabIndex={7}
                                        disabled={isLoginButtonDisabled}
                                        className="btn btn-primary btn-lg"
                                        name="login"
                                        id="kc-login"
                                        type="submit"
                                        style={{ width: "100%" }}
                                    >
                                        {msgStr("doLogIn")} →
                                    </button>
                                </form>
                            )}

                            {realm.password && realm.registrationAllowed && !registrationDisabled && (
                                <p style={{ marginTop: 24, fontSize: 13, color: "var(--ink-300)", textAlign: "center" }}>
                                    {msg("noAccount")}{" "}
                                    <a tabIndex={8} href={url.registrationUrl} style={{ color: "var(--orange-500)", textDecoration: "none", fontWeight: 500 }}>
                                        {msg("doRegister")}
                                    </a>
                                </p>
                            )}
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

function PasswordInput(props: { i18n: I18n; hasError: boolean }) {
    const { i18n, hasError } = props;
    const { msgStr } = i18n;
    const { isPasswordRevealed, toggleIsPasswordRevealed } = useIsPasswordRevealed({ passwordInputId: "password" });

    return (
        <div className="lp-input-wrap">
            <input
                tabIndex={3}
                id="password"
                className="lp-input"
                name="password"
                type={isPasswordRevealed ? "text" : "password"}
                autoComplete="current-password"
                aria-invalid={hasError}
                style={{ paddingRight: 64 }}
            />
            <button
                type="button"
                className="lp-reveal"
                aria-label={msgStr(isPasswordRevealed ? "hidePassword" : "showPassword")}
                aria-controls="password"
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


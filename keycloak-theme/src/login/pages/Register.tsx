import { useEffect, useState } from "react";
import { kcSanitize } from "keycloakify/lib/kcSanitize";
import type { PageProps } from "keycloakify/login/pages/PageProps";
import type { KcContext } from "../KcContext";
import type { I18n } from "../i18n";
import { BrandPanel } from "../BrandPanel";

// Registration page (register.ftl) restyled to match the two-panel login.
// LEFT = the sign-up form (hand-built standard fields + captcha + terms, so
// it follows the .lp design rather than the default user-profile/PatternFly
// markup). RIGHT = the shared BrandPanel. Posts to url.registrationAction
// exactly like the default page.
export default function Register(props: PageProps<Extract<KcContext, { pageId: "register.ftl" }>, I18n>) {
    const { kcContext, i18n, Template, doUseDefaultCss, classes } = props;
    const {
        url,
        realm,
        messagesPerField,
        message,
        recaptchaRequired,
        recaptchaVisible,
        recaptchaSiteKey,
        recaptchaAction,
        termsAcceptanceRequired
    } = kcContext;
    const { msg, msgStr } = i18n;

    const [termsAccepted, setTermsAccepted] = useState(false);

    // Visible reCAPTCHA needs the Google widget script. Our Template is a
    // pass-through (no default scripts), so load it here when required.
    useEffect(() => {
        if (!recaptchaRequired) return;
        const id = "kc-recaptcha-script";
        if (document.getElementById(id)) return;
        const s = document.createElement("script");
        s.id = id;
        s.src = "https://www.google.com/recaptcha/api.js";
        s.async = true;
        s.defer = true;
        document.head.appendChild(s);
    }, [recaptchaRequired]);

    const fieldError = (name: string) =>
        messagesPerField.existsError(name) ? (
            <div
                className="lp-field-error"
                aria-live="polite"
                dangerouslySetInnerHTML={{ __html: kcSanitize(messagesPerField.get(name)) }}
            />
        ) : null;

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
                                ← Back to sign in
                            </a>
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
                        </div>

                        <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", maxWidth: 460, paddingTop: 24, paddingBottom: 24 }}>
                            <h1 style={{ fontSize: 34, lineHeight: 1.1, letterSpacing: "-0.025em", fontWeight: 500, margin: 0, color: "var(--ink-100)" }}>
                                Create your{" "}
                                <span style={{ fontStyle: "italic", fontWeight: 400, fontFamily: "'IBM Plex Serif', serif", color: "var(--orange-500)" }}>
                                    account
                                </span>
                                .
                            </h1>
                            <p style={{ marginTop: 12, fontSize: 15, lineHeight: 1.55, color: "var(--ink-300)", marginBottom: 28 }}>
                                Sign up for the developer portal. You get basic access right away — your platform admins manage which APIs you can see.
                            </p>

                            {message !== undefined && (
                                <div className={`lp-banner ${message.type}`} dangerouslySetInnerHTML={{ __html: kcSanitize(message.summary) }} />
                            )}

                            <form id="kc-register-form" action={url.registrationAction} method="post">
                                <div className="lp-field-row">
                                    <div className="lp-field" style={{ flex: 1 }}>
                                        <label htmlFor="firstName" className="lp-label">{msg("firstName")}</label>
                                        <input id="firstName" className="lp-input" name="firstName" type="text" autoFocus autoComplete="given-name" aria-invalid={messagesPerField.existsError("firstName")} />
                                        {fieldError("firstName")}
                                    </div>
                                    <div className="lp-field" style={{ flex: 1 }}>
                                        <label htmlFor="lastName" className="lp-label">{msg("lastName")}</label>
                                        <input id="lastName" className="lp-input" name="lastName" type="text" autoComplete="family-name" aria-invalid={messagesPerField.existsError("lastName")} />
                                        {fieldError("lastName")}
                                    </div>
                                </div>

                                <div className="lp-field">
                                    <label htmlFor="email" className="lp-label">{msg("email")}</label>
                                    <input id="email" className="lp-input" name="email" type="email" autoComplete="email" aria-invalid={messagesPerField.existsError("email")} />
                                    {fieldError("email")}
                                </div>

                                {!realm.registrationEmailAsUsername && (
                                    <div className="lp-field">
                                        <label htmlFor="username" className="lp-label">{msg("username")}</label>
                                        <input id="username" className="lp-input" name="username" type="text" autoComplete="username" aria-invalid={messagesPerField.existsError("username")} />
                                        {fieldError("username")}
                                    </div>
                                )}

                                <div className="lp-field">
                                    <label htmlFor="password" className="lp-label">{msg("password")}</label>
                                    <input id="password" className="lp-input" name="password" type="password" autoComplete="new-password" aria-invalid={messagesPerField.existsError("password")} />
                                    {fieldError("password")}
                                </div>

                                <div className="lp-field">
                                    <label htmlFor="password-confirm" className="lp-label">{msg("passwordConfirm")}</label>
                                    <input id="password-confirm" className="lp-input" name="password-confirm" type="password" autoComplete="new-password" aria-invalid={messagesPerField.existsError("password-confirm")} />
                                    {fieldError("password-confirm")}
                                </div>

                                {termsAcceptanceRequired && (
                                    <div style={{ margin: "4px 0 18px" }}>
                                        <label style={{ display: "flex", alignItems: "flex-start", gap: 10, fontSize: 13, color: "var(--ink-300)", lineHeight: 1.45 }}>
                                            <input
                                                type="checkbox"
                                                id="termsAccepted"
                                                name="termsAccepted"
                                                checked={termsAccepted}
                                                onChange={e => setTermsAccepted(e.target.checked)}
                                                style={{ marginTop: 2 }}
                                            />
                                            <span dangerouslySetInnerHTML={{ __html: kcSanitize(msgStr("termsText")) }} />
                                        </label>
                                        {fieldError("termsAccepted")}
                                    </div>
                                )}

                                {recaptchaRequired && (recaptchaVisible || recaptchaAction === undefined) && (
                                    <div style={{ marginBottom: 18 }}>
                                        <div className="g-recaptcha" data-size="normal" data-sitekey={recaptchaSiteKey} data-action={recaptchaAction} />
                                    </div>
                                )}

                                <button
                                    type="submit"
                                    className="btn btn-primary btn-lg"
                                    style={{ width: "100%" }}
                                    disabled={termsAcceptanceRequired && !termsAccepted}
                                >
                                    {msgStr("doRegister")} →
                                </button>
                            </form>

                            <p style={{ marginTop: 22, fontSize: 13, color: "var(--ink-300)", textAlign: "center" }}>
                                Already have an account?{" "}
                                <a href={url.loginUrl} style={{ color: "var(--orange-500)", textDecoration: "none", fontWeight: 500 }}>
                                    Sign in
                                </a>
                            </p>
                        </div>

                        <div
                            style={{
                                paddingTop: 20,
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

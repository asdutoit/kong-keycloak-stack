<#--
  Shared navy/orange .lp email shell + helpers, so every themed email
  (password-reset, executeActions, email-verification) is identical in chrome
  and only the copy differs. Email-safe: table layout + inline styles +
  web-safe font fallbacks. Emails can't run React, so this is FreeMarker.

  Usage:
    <#import "lp-email.ftl" as lp>
    <@lp.shell eyebrow="Account security" heading="Reset your password">
       ...body paragraphs...
       <@lp.button href=link label="Reset password &rarr;"/>
       ...
    </@lp.shell>
-->
<#assign sans = "'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
<#assign mono = "'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace">

<#macro shell eyebrow heading preheader="">
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta name="color-scheme" content="dark" />
  <title>${heading}</title>
</head>
<body style="margin:0; padding:0; background-color:#070f1c; -webkit-font-smoothing:antialiased;">
  <div style="display:none; max-height:0; overflow:hidden; opacity:0;">${preheader}</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#070f1c;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px; width:100%;">
          <tr>
            <td style="padding:4px 8px 20px 8px;">
              <span style="font-family:${mono}; font-size:13px; font-weight:600; letter-spacing:0.04em; color:#d9dce3; text-transform:uppercase;">
                <span style="color:#e8843f;">&#9670;</span>&nbsp; API Onboarding
              </span>
            </td>
          </tr>
          <tr>
            <td style="background-color:#0f1d33; border:1px solid #1e2f4d; border-radius:10px; padding:40px 40px 36px 40px;">
              <p style="margin:0 0 6px 0; font-family:${mono}; font-size:11px; letter-spacing:0.14em; text-transform:uppercase; color:#e8843f;">${eyebrow}</p>
              <h1 style="margin:0 0 16px 0; font-family:${sans}; font-size:26px; line-height:1.25; font-weight:500; color:#f2eee5;">${heading}</h1>
              <#nested>
            </td>
          </tr>
          <tr>
            <td style="padding:20px 8px 8px 8px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="font-family:${mono}; font-size:11px; letter-spacing:0.04em; color:#4a5a78;">KEYCLOAK SSO &middot; OIDC</td>
                  <td align="right" style="font-family:${mono}; font-size:11px; letter-spacing:0.04em; color:#4a5a78;">API ONBOARDING PORTAL</td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
</#macro>

<#-- body paragraph -->
<#macro p>
<p style="margin:0 0 16px 0; font-family:${sans}; font-size:15px; line-height:1.6; color:#a6b3cc;"><#nested></p>
</#macro>

<#-- orange CTA button -->
<#macro button href label>
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:12px 0 0 0;">
  <tr>
    <td align="center" bgcolor="#e8843f" style="border-radius:6px;">
      <a href="${href}" target="_blank" style="display:inline-block; padding:13px 28px; font-family:${sans}; font-size:15px; font-weight:600; color:#1a0d05; text-decoration:none; border-radius:6px;">${label}</a>
    </td>
  </tr>
</table>
</#macro>

<#-- paste-able fallback link block -->
<#macro linkbox href>
<p style="margin:28px 0 8px 0; font-family:${sans}; font-size:12.5px; line-height:1.5; color:#6e7e9c;">Or paste this link into your browser:</p>
<p style="margin:0 0 8px 0; font-family:${mono}; font-size:12px; line-height:1.5; word-break:break-all;">
  <a href="${href}" target="_blank" style="color:#f0a06a; text-decoration:none;">${href}</a>
</p>
</#macro>

<#-- thin divider + muted security note -->
<#macro note>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
  <tr><td style="border-top:1px solid #1e2f4d; font-size:0; line-height:0; height:1px;">&nbsp;</td></tr>
</table>
<p style="margin:24px 0 0 0; font-family:${sans}; font-size:13px; line-height:1.6; color:#6e7e9c;"><#nested></p>
</#macro>

<#-- Password-reset email for the api-portal theme. Standalone HTML (no base
     layout) so the navy/orange .lp design language carries into the inbox.
     Email-safe: table layout + inline styles + web-safe font fallbacks. -->
<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta name="color-scheme" content="dark" />
  <title>Reset your password</title>
</head>
<body style="margin:0; padding:0; background-color:#070f1c; -webkit-font-smoothing:antialiased;">
  <!-- preheader (hidden) -->
  <div style="display:none; max-height:0; overflow:hidden; opacity:0;">Reset the password for your API Onboarding Portal account.</div>

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#070f1c;">
    <tr>
      <td align="center" style="padding:32px 16px;">

        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px; width:100%;">

          <!-- Brand -->
          <tr>
            <td style="padding:4px 8px 20px 8px;">
              <span style="font-family:'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace; font-size:13px; font-weight:600; letter-spacing:0.04em; color:#d9dce3; text-transform:uppercase;">
                <span style="color:#e8843f;">&#9670;</span>&nbsp; API Onboarding
              </span>
            </td>
          </tr>

          <!-- Card -->
          <tr>
            <td style="background-color:#0f1d33; border:1px solid #1e2f4d; border-radius:10px; padding:40px 40px 36px 40px;">

              <p style="margin:0 0 6px 0; font-family:'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace; font-size:11px; letter-spacing:0.14em; text-transform:uppercase; color:#e8843f;">
                Account security
              </p>

              <h1 style="margin:0 0 16px 0; font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:26px; line-height:1.25; font-weight:500; color:#f2eee5;">
                Reset your password
              </h1>

              <p style="margin:0 0 14px 0; font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; line-height:1.6; color:#a6b3cc;">
                <#if user?? && user.firstName??>Hi ${user.firstName},<#else>Hi,</#if>
              </p>

              <p style="margin:0 0 28px 0; font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; line-height:1.6; color:#a6b3cc;">
                We received a request to reset the password for your API Onboarding Portal account. Click the button below to choose a new one. This link expires in ${linkExpirationFormatter(linkExpiration)}.
              </p>

              <!-- CTA -->
              <table role="presentation" cellpadding="0" cellspacing="0">
                <tr>
                  <td align="center" bgcolor="#e8843f" style="border-radius:6px;">
                    <a href="${link}" target="_blank"
                       style="display:inline-block; padding:13px 28px; font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:15px; font-weight:600; color:#1a0d05; text-decoration:none; border-radius:6px;">
                      Reset password &rarr;
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin:28px 0 8px 0; font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:12.5px; line-height:1.5; color:#6e7e9c;">
                Or paste this link into your browser:
              </p>
              <p style="margin:0 0 8px 0; font-family:'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace; font-size:12px; line-height:1.5; word-break:break-all;">
                <a href="${link}" target="_blank" style="color:#f0a06a; text-decoration:none;">${link}</a>
              </p>

              <!-- Divider -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                <tr><td style="border-top:1px solid #1e2f4d; font-size:0; line-height:0; height:1px;">&nbsp;</td></tr>
              </table>

              <p style="margin:24px 0 0 0; font-family:'IBM Plex Sans',-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.6; color:#6e7e9c;">
                Didn&rsquo;t request this? You can safely ignore this email &mdash; your password won&rsquo;t change until you open the link above and set a new one.
              </p>

            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding:20px 8px 8px 8px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="font-family:'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace; font-size:11px; letter-spacing:0.04em; color:#4a5a78;">
                    KEYCLOAK SSO &middot; OIDC
                  </td>
                  <td align="right" style="font-family:'IBM Plex Mono',ui-monospace,Menlo,Consolas,monospace; font-size:11px; letter-spacing:0.04em; color:#4a5a78;">
                    API ONBOARDING PORTAL
                  </td>
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

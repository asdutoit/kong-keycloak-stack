<#import "lp-email.ftl" as lp>
<@lp.shell eyebrow="Account security" heading="Reset your password" preheader="Reset the password for your API Onboarding Portal account.">
<@lp.p>Hi <#if user?? && user.firstName??>${user.firstName}<#else>there</#if>,</@lp.p>
<@lp.p>We received a request to reset the password for your API Onboarding Portal account. Click the button below to choose a new one. This link expires in ${linkExpirationFormatter(linkExpiration)}.</@lp.p>
<@lp.button href=link label="Reset password →"/>
<@lp.linkbox href=link/>
<@lp.note>Didn&rsquo;t request this? You can safely ignore this email &mdash; your password won&rsquo;t change until you open the link above and set a new one.</@lp.note>
</@lp.shell>

<#import "lp-email.ftl" as lp>
<@lp.shell eyebrow="Verify email" heading="Confirm your email address" preheader="Confirm your email to activate your API Onboarding Portal account.">
<@lp.p>Hi <#if user?? && user.firstName??>${user.firstName}<#else>there</#if>,</@lp.p>
<@lp.p>Confirm this email address to activate your API Onboarding Portal account. Click the button below to verify it&rsquo;s really you. This link expires in ${linkExpirationFormatter(linkExpiration)}.</@lp.p>
<@lp.button href=link label="Verify email →"/>
<@lp.linkbox href=link/>
<@lp.note>If you didn&rsquo;t create this account, you can safely ignore this email.</@lp.note>
</@lp.shell>

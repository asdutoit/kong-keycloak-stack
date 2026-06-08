<#import "lp-email.ftl" as lp>
<@lp.shell eyebrow="Action required" heading="Finish setting up your account" preheader="Your administrator asked you to update your account.">
<@lp.p>Hi <#if user?? && user.firstName??>${user.firstName}<#else>there</#if>,</@lp.p>
<@lp.p>Your administrator has asked you to update your API Onboarding Portal account<#if requiredActions??> by completing: <#list requiredActions><#items as reqAction>${msg("requiredAction.${reqAction}")}<#sep>, </#items></#list></#if>. Click the button below to continue. This link expires in ${linkExpirationFormatter(linkExpiration)}.</@lp.p>
<@lp.button href=link label="Continue →"/>
<@lp.linkbox href=link/>
<@lp.note>If you weren&rsquo;t expecting this, you can safely ignore this email.</@lp.note>
</@lp.shell>

# Identity & Access Management: Protocols, Products, and Patterns

## 1. Protocols vs. products

The first thing to get straight is that some of these names are protocols and some are products that speak those protocols. Mixing them up is where most of the confusion comes from.

| Layer | Technology | What it does | Speaks / runs over |
|---|---|---|---|
| Directory protocol | LDAP / LDAPS | Hierarchical lookups and credential checks | TCP 389 / 636 |
| Federation protocol | SAML 2.0 | Enterprise web SSO, cross-domain assertions | XML over HTTP (POST / Redirect) |
| Federation protocol | OAuth 2.0 | Delegated API authorization (access tokens) | JSON over HTTPS |
| Federation protocol | OpenID Connect (OIDC) | Authentication layer on top of OAuth 2.0 | JWTs over HTTPS |
| On-prem directory | Active Directory (AD DS) | Corporate directory and network auth | LDAP, Kerberos, NTLM, DNS |
| Cloud IdP | Microsoft Entra ID | Managed workforce and B2B/B2C identity | OIDC, OAuth 2.0, SAML, Graph API |
| Self-hosted IdP | Keycloak / Authentik | Full IdP you run yourself | OIDC, SAML, OAuth 2.0, LDAP federation |

## 2. The protocols

### LDAP (Lightweight Directory Access Protocol)

LDAP is a wire protocol for reading and searching a directory quickly. Entries live in a tree (the Directory Information Tree, or DIT), and each one is addressed by a Distinguished Name:

```
uid=alice,ou=engineering,dc=company,dc=com
```

Authentication is a **bind**: the client sends a DN and a password, and the server says yes or no. That's the whole exchange. It's a single request and response over a long-lived TCP connection, which is great for an app server checking a password and useless for anything involving a browser. There's no concept of redirects, browser sessions, or a multi-step MFA challenge.

### SAML 2.0 (Security Assertion Markup Language)

SAML is the XML-based federation standard that most older enterprise apps and a lot of B2B SaaS still rely on. Two roles matter:

- **Identity Provider (IdP)** authenticates the user and issues a signed XML document, the *assertion*.
- **Service Provider (SP)** is the application. It trusts assertions signed by the IdP.

Assertions are bulky and usually travel through the browser via an HTTP POST binding. It's verbose, but it works, and the trust setup between IdP and SP is well understood in enterprise environments.

### OAuth 2.0 and OpenID Connect

These two get conflated constantly, so it's worth being precise:

- **OAuth 2.0 is about authorization.** It issues scoped access tokens so an app can call an API on a user's behalf without ever seeing their password. On its own it says nothing reliable about *who* the user is.
- **OIDC is about authentication.** It's a thin identity layer on top of OAuth 2.0 that adds:
  - the **ID token**, a signed JWT with identity claims (`sub`, `email`, `roles`, …)
  - a discovery document at `/.well-known/openid-configuration`
  - a `/userinfo` endpoint for profile data

OIDC has largely replaced SAML for new apps because it's JSON instead of XML, works naturally in SPAs and mobile apps, and tokens can be verified locally with a public key (RS256, EdDSA) without calling back to the IdP.

## 3. The products

### Active Directory Domain Services (AD DS)

The classic on-prem directory running on Windows Server. It runs the corporate network through Kerberos, NTLM, and LDAP.

What it isn't is a web IdP. AD can't hand an OIDC token to a React app or a cloud service on its own; you need something in between, such as AD FS, Keycloak, or Entra Connect syncing into Entra ID.

### Microsoft Entra ID (formerly Azure AD)

Microsoft's fully managed, SaaS identity service.

Despite the old name, **it isn't Active Directory in the cloud.** It doesn't expose LDAP or traditional Kerberos domain services. If you need those, you add Entra Domain Services on top. Entra ID is built for web protocols (OIDC, OAuth 2.0, SAML) and is managed through the Microsoft Graph API.

Where it shines is the Microsoft ecosystem: Microsoft 365 and Intune integration out of the box, plus risk-based Conditional Access.

### Keycloak vs. Authentik

Both are open-source IdPs you host yourself and put in front of your own apps, APIs, and directories.

| | Keycloak | Authentik |
|---|---|---|
| Maintained by | Red Hat, CNCF project | Authentik Security Inc. and community |
| Language | Java (Quarkus) | Python and Go |
| Feel | Heavyweight, battle-tested, extensible through SPIs | Lighter, flow-based, ships with its own reverse proxy (outpost) |
| Database | PostgreSQL, MySQL, MariaDB, Oracle, MSSQL | PostgreSQL (Redis no longer required as of 2025.10) |
| Good fit for | Large enterprise apps, high-throughput microservices, complex token mapping | Homelabs, container stacks, anything that needs proxy auth in front of apps that have none |

### A note on AWS

AWS IAM is a different animal from the IdPs above, and it's easy to lump them together by mistake:

- **AWS IAM** controls access to AWS resources (S3, EC2, RDS, …). It can't put a login page in front of your web app.
- **IAM Identity Center** (formerly AWS SSO) is the workforce side: single sign-on into AWS accounts and SaaS apps. It fills roughly the same role Entra ID does for Microsoft shops, and it's often federated *to* Entra ID or Okta.
- **Amazon Cognito** is the developer-facing user pool for your own application's users. That's the closest AWS gets to Keycloak or Authentik.

## 4. Integration patterns

### Pattern A: User federation

The IdP checks credentials against an existing directory (LDAP or AD) instead of storing passwords itself.

```
[ Browser ]                     [ IdP ]                        [ LDAP / AD ]
     |                              |                                |
     |  1. Submit credentials       |                                |
     |----------------------------->|                                |
     |                              |  2. LDAP bind as the user      |
     |                              |------------------------------->|
     |                              |  3. Bind succeeds (result 0)   |
     |                              |<-------------------------------|
     |                              |                                |
     |                              |  4. Copy attributes locally,   |
     |                              |     assign IdP roles/groups    |
     |                              |                                |
     |  5. Issue OIDC tokens        |                                |
     |<-----------------------------|                                |
```

- **Passwords stay in LDAP/AD.** The IdP checks them over a back channel and never stores them.
- **The IdP keeps a local copy of the user** (username, email, groups, an internal ID). That makes token issuance fast and gives you somewhere to hang IdP-specific roles that the directory doesn't know about.

### Pattern B: Identity brokering

The local IdP hands authentication off to an upstream IdP and then issues its own tokens.

```
[ Browser ]               [ Broker IdP (Keycloak) ]        [ Upstream IdP (Entra ID / Google) ]
     |                              |                                |
     |  1. "Sign in with M365"      |                                |
     |----------------------------->|                                |
     |                              |  2. Redirect to upstream       |
     |                              |------------------------------->|
     |  3. Log in upstream (MFA, passkey, Conditional Access)        |
     |-------------------------------------------------------------->|
     |                              |  4. Callback with token or     |
     |                              |     assertion                  |
     |                              |<-------------------------------|
     |                              |                                |
     |                              |  5. Validate, map claims       |
     |                              |                                |
     |  6. Issue local app tokens   |                                |
     |<-----------------------------|                                |
```

The payoff is decoupling. Your apps only ever talk to Keycloak or Authentik. If you move from Google to Entra ID, you reconfigure the broker and the application code doesn't change.

## 5. Where MFA belongs

**Put MFA in the IdP, not in LDAP.**

An LDAP bind is one request and one answer. There's no way for it to run an interactive exchange with a browser, so WebAuthn/FIDO2, TOTP prompts, and push approvals can't be expressed through it.

What works well in practice:

- **First factor (password):** checked against LDAP / AD.
- **Second factor (TOTP, WebAuthn):** enrolled, stored, and verified by the IdP itself in its own database.

You get passkeys and authenticator apps without touching the AD schema.

## 6. Putting it together

A typical enterprise setup layers all of this:

```
+----------------------------------------------------------------------------+
|                          End-user applications                             |
|              (React SPAs, mobile apps, APIs, internal dashboards)          |
+----------------------------------------------------------------------------+
                                      │
                                      ▼  OIDC / OAuth 2.0 tokens
+----------------------------------------------------------------------------+
|                     Identity broker (Keycloak)                             |
|  - Application clients, secrets, and scopes                                |
|  - App-level roles and permissions                                         |
|  - MFA (WebAuthn / TOTP)                                                   |
+----------------------------------------------------------------------------+
                  │                                       │
       User federation (LDAP)                 Identity brokering (OIDC / SAML)
                  │                                       │
                  ▼                                       ▼
+--------------------------------+     +-------------------------------------+
|   On-prem Active Directory     |     |          Microsoft Entra ID         |
|  - Legacy corporate users      |     |  - Workforce accounts               |
|  - Password authority          |     |  - Device compliance, Cond. Access  |
+--------------------------------+     +-------------------------------------+
```

Apps see one IdP. Behind it, legacy users authenticate against AD and everyone else comes in through Entra ID, with MFA and app roles handled consistently in the middle.

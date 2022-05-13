**Validated: 2022/05/13**

# Tezos CI Deployment

## Pre Requistes

The tezos-ci pipeline is closely integrated with gitlab.com and the
repositories hosted under tezos and nomadic-labs.

To support this integration it needs:

 * a bot account created with access to both organisations;
 * a GitLab Application created to support oauth logins;
 * register project webhooks for each project to build.

### Tezos Bot Account

tezo-ci requires an account to exist, ideally a separate bot account
with sufficient access to update commit and merge request statuses on
the projects being built. Once a suitable bot account has been
created, login as that account, visit
<https://gitlab.com/-/profile/personal_access_tokens> and create a
Personal Access Token for tezos-ci. Use the following information:

``` yaml
  Token name: tezos-ci
  Expiration date: None (or choose a suitable timeframe for rotating credentials)
  Select scopes: api, read_repository
```

Record the personal access token generated as it needs to be supplied
to the application as cli arguments.

### GitLab Application

The GitLab Application supports peforming oauth logins in tezos-ci,
some functionality like rebuilds and cancels can be protected by
requiring a logged in user. In future more funcionality could be added
that requires oauth logins.

To setup login as the bot user, go to
<https://gitlab.com/oauth/applications> and fill in the following
information:

``` yaml
  Name: tezos-ci
  Redirect URI: <https://gitlab.tezos.ci.dev:8100/login>
  Scopes: read_user (Read the authenticated user's personal information)
```

Record the application id and secret as they need to be supplied to
the application as cli arguments.

For the oauth token configuration file the format is:

``` json
{
    "client_id": "????",
    "client_secret": "????",
    "scopes": ["read_user"],
    "redirect_uri": "https://gitlab.tezos.ci.dev:8100/login"
}
```

### Register Project webhooks

For tezos-ci to follow activity on a repository, it needs to register
webhook notifications with individual projects.  In the future this
can be automated but for now it is a manual process. To add webhooks
for a project go to the project hooks page: for tezos/tezos that would
be <https://gitlab.com/tezos/tezos/-/hooks> and fill in the following
information:

Url: <https://gitlab.tezos.ci.dev/webhooks/gitlab>\
Secret: private chosen value to authenticate webhooks\
Trigger: Push events, Tag push events, Merge request events\
SSL verification: Enable SSL verification

On save test out creating a Merge Request and check the Recent events
section of the hooks page to validate everything is working.

### Deployment and Secrets

tezos-ci uses docker for deployment and stores secrets like
application id and webhook secrets as docker secrets. The service
configuration is managed in Ansible as docker stacks / services. For
how to update / create new configuration values consult the ansible
playbook.
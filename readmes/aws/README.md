# Use of aws aliases and commands

## Aliases

There are several custom aliases with the `aws cli` and `aws-vault` commands:

### AWS Cli

* `aspl` - list profiles from `~/.aws/config`
* `asp <profile>` - set to `AWS_...` profiles environments the chosen profile - used also from `aws-vault`
* `aws-unset-session` - clear all `AWS_...` session variables

## AWS Vault

* `awsv` - list profiles and credentials from `aws-vault`
* `awsvl <profile>` - login in default `${BROWSER}` which is `google-chrome` to selected profile
* `awsvlp <profile>` - login in private session in default `${BROWSER}` which is `google-chrome` to selected profile
* `awsve <profile>` - generate and export the env variables for `AWS_...` session
* `awsvep <profile>` - generate and only print the env variables for `AWS_...` session

## YubiKey Setup

Add the MFA secret from AWS with the MFA ARN name:
```bash
ykman oath accounts add arn:aws:iam::891584517969:mfa/ivan.dachev ZKFG...
```

You can store the secret and add it in Google auth on mobile for backup.

Setup in `~/.aws/config` the MFA credentials:
```bash
credential_process=aws-vault exec <profile name> --json --prompt=ykman
```

## Troubleshooting

Sometimes need to restart the `pcscd` service:
```bash
sudo service pcscd restart
```

For git sometimes need to restart its credential cache:
```bash
killall git-credential-cache--daemon
```

Used through git it appends its own LD library part, which breaks ykman and other prompts.

Use this script instead of `aws-vault` in `credential_process`:
```bash
credential_process=aws-vault-from-git.sh exec...
```


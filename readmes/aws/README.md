# Use of aws aliases and commands

There are several custom aliases created to be used with the `aws cli` and `aws-vault` command.

* `aspl` - list profiles from `~/.aws/config`
* `asp <profile>` - set to `AWS_...` profiles environments the chosen profile - used also from `aws-vault`
* `aws-unset-session` - clear all `AWS_...` session variables

## aws-vault
* `awsv` - list profiles and credentials from `aws-vault`
* `awsvl <profile>` - login in default `${BROWSER}` which is `google-chrome` to selected profile
* `awsvlp <profile>` - login in private session in default `${BROWSER}` which is `google-chrome` to selected profile
* `awsve <profile>` - generate and export the env variables for `AWS_...` session
* `awsvep <profile>` - generate and only print the env variables for `AWS_...` session

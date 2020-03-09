#!/bin/bash

SSH_AGENT_EXPORT_FILE="${HOME}/.ssh_agent_export"

rm "${SSH_AGENT_EXPORT_FILE}"
touch "${SSH_AGENT_EXPORT_FILE}" 
echo "export SSH_AGENT_PID=${SSH_AGENT_PID}" >> "${SSH_AGENT_EXPORT_FILE}"
echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >> "${SSH_AGENT_EXPORT_FILE}"

echo -e "Export complete, execute:\nsource ${SSH_AGENT_EXPORT_FILE}"


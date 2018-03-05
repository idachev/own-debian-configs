#!/bin/bash

echo -e "\nGenerating server key"
openssl genrsa -out server.key 2048

echo -e "\nGenerating cert"
openssl req -new -out server.csr -key server.key

echo -e "\nSign cert"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

echo -e "\nCreating store"
openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12 -name restapi -CAfile server.crt -caname root


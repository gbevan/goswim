## Dev Notes

### Running in vagrant
```
$ vagrant up
$ vagrant ssh
vagrant~$ go get github.com/gbevan/godo/cmd/godo
vagrant~$ cd go/src/github.com/gbevan/gostint/
vagrant~$ dep ensure
vagrant~$ godo [--watch]
```
in another terminal you can run the BATS tests:
```
$ vagrant ssh
vagrant~$ cd go/src/github.com/gbevan/gostint/
vagrant~$ godo test
```

#### Accessing mongodb in vagrant
```
vagrant~$ mongo -u gostint_admin -p admin123 admin
> use gostint
> db.queues.find()
```

### Testing Ephemeral user/password for MongoDB
`vagrant ssh` into the container
```
~$ vault login root
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                root
token_accessor       0a4e9bad-768b-3f2d-be35-afdb0b6f35c1
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]

~$ vault read database/creds/gostint-dbauth-role
Key                Value
---                -----
lease_id           database/creds/gostint-dbauth-role/9f12e958-a2e7-080e-e9df-b8842cb3f8ae
lease_duration     1h
lease_renewable    true
password           A1a-4bHwB9x6vd6irH51
username           v-token-gostint-dbauth-role-g0YkRCwmxnbnTcFh0oQ8-1530388299
```
See [godo](Gododir/main.go) for dev testing the above.

### Get a SecretId for the gostint-role for a request
```
~$ vault write -f auth/approle/role/gostint-role/secret-id
Key                   Value
---                   -----
secret_id             1b3932e2-2e76-c2bf-f962-8115359a8b05
secret_id_accessor    7a175626-3f19-9f74-377a-12a3b8c2b9db

```
This `secret_id` can be passed on any requests to run jobs (see below).
### Create a KV Secret to test with
```
vault kv put secret/my-secret my-value=s3cr3t
```
Get it back
```
vault kv get secret/my-secret
```
see `Gododir/main.go`

### Run containered Jobs using curl
```
$ curl -k -s https://127.0.0.1:3232/v1/api/job \
  -X POST \
  -d @job3_shell_content.json \
  --header 'X-Secret-Token: 21797b7e-589b-af25-a0e3-341974e5992b' \
  | jq
{
  "_id": "5b3f83d3559214025a198281",
  "status": "queued",
  "qname": "play"
}
```
The `X-Secret-Token` is the Approle's SecretID from above step. This is
combined with the application's RoleID to Authenticate with Vault and to
be issued with a Token for this job run.  This Token, plus any referenced
secrets will be injected into the running containerised job as `/secrets.yaml`.

For some example job JSON files see [tests/](tests/)

### Retrieve Status and Results of a job using curl
```
$ curl -k -s https://127.0.0.1:3232/v1/api/job/5b3f83d3559214025a198281 \
  --header 'X-Secret-Token: 21797b7e-589b-af25-a0e3-341974e5992b' \
  | jq
{
  "_id": "5b3f83d3559214025a198281",
  "status": "success",
  "node_uuid": "c95318ae-fab0-40cf-82f1-3809fa58a473",
  "qname": "play",
  "container_image": "",
  "submitted": "2018-07-06T14:59:31.014Z",
  "started": "2018-07-06T14:59:31.817Z",
  "ended": "2018-07-06T14:59:34.266Z",
  "output": "Hello World!\r\nHOSTNAME=7c487ca858ce\r\nSHLVL=1\r\nHOME=/root\r\nTERM=xterm\r\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\r\nPWD=/\r\nPID   USER     TIME  COMMAND\r\n    1 root      0:00 {hello.sh} /bin/sh /gostint/hello.sh\r\n    8 root      0:00 ps -efl\r\n-r--r--r--    1 root     root           146 Jan  1  1970 \u001b[0;0m/secrets.yml\u001b[m\r\n\r\n/gostint:\r\ntotal 12\r\ndrwxr-xr-x    2 1000     1000          4096 Jul  5 14:09 \u001b[1;34m.\u001b[m\r\ndrwxr-xr-x   13 root     root          4096 Jul  6 14:59 \u001b[1;34m..\u001b[m\r\n-rwxr-xr-x    1 1000     1000           100 Jul  5 14:09 \u001b[1;32mhello.sh\u001b[m\r\n---\r\n# gostint vault secrets injected:\r\nTOKEN: c2eaebd4-cde3-8cda-1692-fe3647d48895\r\nfield_1: value1\r\nfield_2: value2\r\nfield_3: value3\r\nmysecret: s3cr3t\r\n",
  "return_code": 0
}
```
The url path takes the `_id` hex string returned from submitting the job as
a key.
Returned statuses can be:

| Status          | Description                              |
|-----------------|------------------------------------------|
| `queued`        | Job has been queued                      |
| `notauthorised` | Job failed authentication with Vault     |
| `running`       | Job is currently running                 |
| `stopping`      | Job is currently stopping for a kill req |
| `failed`        | Job has failed                           |
| `success`       | Job has succeeded                        |

### Killing a job by jobID
```
curl -k -s https://127.0.0.1:3232/v1/api/job/kill/5b4246f1e1c2cc22c776d734 \
  --header 'X-Secret-Token: 8447c783-51c3-3d82-8415-0df657d70dc8' \
  -X POST \
  | jq
{
  "_id": "5b4246f1e1c2cc22c776d734",
  "container_id": "fee2da7bb3f95b09bb713b4d8520044c7eaff5a98a516ead66924cd74a62e3f7",
  "status": "stopping"
}

gostint will attempt to first stop the container and will timeout after 15
seconds and then will kill it.
```

### Deleting a job
```
curl -k -s https://127.0.0.1:3232/v1/api/job/5b4258fee1c2cc29d1c687d1 \
  --header 'X-Secret-Token: 8447c783-51c3-3d82-8415-0df657d70dc8' \
  -X DELETE \
  | jq
{
  "_id": "5b4258fee1c2cc29d1c687d1"
}

```
WARNING: currently this can delete a running/stopping job - this will be fixed
soon...

### Creating content to inject into the container for execution

```
cd yourcontent/
tar zcvf ../yourcontent.tar.gz .
base64 -w 0 < ../yourcontent.tar.g
```
Copy & Paste the resulting base64 into the `content: "..."` field in the job json

### Reading secrets.yml into a shell script

You can run any script in the job container using the
[yamlsh](https://github.com/gbevan/yamlsh) tool to parse the secrets.yml
file into your script at runtime.

```
#!/usr/local/bin/yamlsh --yaml=/secrets.yml
...
```

# Releasing with goreleaser and docker
Merges of PRs to goethite/gostint master will trigger `devel` builds of
the docker image automatically in DockerHub.

Versioned releases:
```
./release.sh v1.0.0 "comment for release..."
```

# duckdb-azure FIPS repro

Minimal reproduction for: **the DuckDB `azure` extension's TLS fails when the
host libcrypto has activated OpenSSL's FIPS provider** under the default
`openssl_conf` app-name.

The failure matches the scenario upstream OpenSSL maintainers describe as
explicitly unsupported in [openssl/openssl#27691][27691]:

> *"We do not support the scenario of an application linked against multiple
> versions of libcrypto … sharing a single `fips.so`."*

The `azure.duckdb_extension` statically links OpenSSL **3.6.0**
([pinned in duckdb-azure `vcpkg.json`][vcpkg]). Running inside Node (which
bundles its own libcrypto, 3.5.7 in Node 22) puts two libcryptos in one
process. When the host config routes the default `openssl_conf` into the FIPS
chain, both libcryptos try to activate FIPS and both `dlopen()` the same
`fips.so` — the unsupported scenario.

## Run it

```bash
docker build --platform=linux/amd64 -t fips-repro .
docker run --rm --platform=linux/amd64 fips-repro
```

Expected output:

```
IO Error: AzureStorageFileSystem could not open file:
'abfss://x@nonexistent.dfs.core.windows.net/foo.parquet', unknown error
occurred, this could mean the credentials used were wrong.
Original error message: 'GetToken(): Fail to get a new connection for:
https://login.microsoftonline.com. SSL connect error'
```

No network credentials or DNS are needed — the TLS handshake in libcurl
fails before any address resolution.

## Evidence that two independent `dlopen()`s hit the same `fips.so`

Run with `LD_DEBUG=files` and filter for `fips.so`:

```bash
docker run --rm --platform=linux/amd64 -e LD_DEBUG=files fips-repro 2>&1 \
  | grep fips.so
```

With the extension loaded (two libcryptos):

```
file=/usr/lib/.../ossl-modules/fips.so [0];  dynamically loaded by node [0]
opening file=/usr/lib/.../ossl-modules/fips.so [0]; direct_opencount=1
opening file=/usr/lib/.../ossl-modules/fips.so [0]; direct_opencount=2
```

Without the extension (Node-only HTTPS) in the same image, `direct_opencount`
stops at **1**.

## Correlation matrix

| Scenario | `fips.so` opencount | TLS result |
|---|---|---|
| `openssl s_client -connect login.microsoftonline.com:443` (one libcrypto) | 1 | **CONNECTION ESTABLISHED, TLSv1.3** |
| Node-only `https.get(...)` (one libcrypto) | 1 | **status 200** |
| Node + `LOAD azure` + `read_parquet('abfss://…')` (two libcryptos) | **2** | **`SSL connect error`** |
| Same, `fips_sect` removed from `[provider_sect]` in `fips.cnf` | 0 | `SSL connect error` goes away |
| Same, with `OPENSSL_DEFAULT_PROVIDER=0` (only gates the `default` provider, not FIPS) | 2 | **`SSL connect error`** |

The `SSL connect error` is tightly correlated with `opencount=2`.

## Impact

Any app running the `azure` extension on a host where another libcrypto has
activated OpenSSL's FIPS provider under the default `openssl_conf` app-name
will see every HTTPS call from the extension fail. This happened to us in
production when the FIPS-hardened Node base image we build on was rebuilt
with a one-line addition to `fips.cnf` that routed `openssl_conf` into the
FIPS chain (previously only the Node-specific `nodejs_conf` was).

## Ask

- Does this diagnosis match how the extension's bundled OpenSSL is initialized?
- Is there a supported way to run the extension on a FIPS-enabled host today?
- What does `duckdb-azure` consider the right path long-term?

[27691]: https://github.com/openssl/openssl/issues/27691
[vcpkg]: https://github.com/duckdb/duckdb-azure/blob/f30be756fbafa5a1ef5f8ea372b81f7fe7916164/vcpkg.json#L10-L13

#!/usr/bin/env python

from OpenSSL import crypto
import re

# Set your CN and SANs here, or use a different means of importing them if you prefer.
cn = "myserv.grid.iu.edu"
sans = ["DNS:myserv.opensciencegrid.org", "DNS:myserv1.grid.iu.edu", "DNS:myserv2.grid.iu.edu"]

# Create key and CSR objects.
key = crypto.PKey()
key.generate_key(crypto.TYPE_RSA, 2048)
csr = crypto.X509Req()

# Write private key to file.
fh = open("./%s_key_py.pem" % cn, "w")
output = crypto.dump_privatekey(crypto.FILETYPE_PEM, key)
# Some versions of PyOpenSSL output BEGIN/END PUBLIC KEY instead of BEGIN/END
# RSA PUBLIC KEY. Work around this.
output = re.sub(r'(-+)(BEGIN|END)(\s+PRIVATE\s+KEY-+)', r'\1\2 RSA\3', output)
fh.write(output)
fh.close()

# Set parameters on CSR object.
csr.set_pubkey(key)
subj = csr.get_subject()
subj.countryName = "US"
subj.stateOrProvinceName = "Indiana"
subj.localityName = "Bloomington"
subj.organizationName = "Indiana University"
subj.organizationalUnitName = "Open Science Grid Operations Center"
subj.CN = cn

# Add SANs, if any, to CSR object.
try:
    sans
except NameError:
    pass
else:
    if isinstance(sans, list) and len(sans) > 0:
        sanext = crypto.X509Extension("subjectAltName", False, ",".join(sans))
        csr.add_extensions([sanext])

# Sign CSR object.
csr.sign(key, "sha512")

# Write CSR to file.
fh = open("./%s_csr_py.pem" % cn, "w")
fh.write(crypto.dump_certificate_request(crypto.FILETYPE_PEM, csr))
fh.close()

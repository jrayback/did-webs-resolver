# -*- encoding: utf-8 -*-
"""
dkr.app.cli.commands module

"""

import argparse
import json
from typing import List

from hio.base import Doer, doing
from keri.app import habbing, oobiing
from keri.app.cli.common import existing
from keri.db import basing
from keri.help import helping

from dkr import log_name, ogler, set_log_level
from dkr.core import didding

parser = argparse.ArgumentParser(description='Resolve a did:keri DID')
parser.set_defaults(handler=lambda args: handler(args), transferable=True)
parser.add_argument('-n', '--name', action='store', default='dkr', help='Name of controller. Default is dkr.')
parser.add_argument(
    '--base', '-b', help='additional optional prefix to file location of KERI keystore', required=False, default=''
)
parser.add_argument(
    '--passcode', help='22 character encryption passcode for keystore (is not saved)', dest='bran', default=None
)  # passcode => bran
parser.add_argument('--did', '-d', help='DID to resolve (did:keri method)', required=True)
parser.add_argument('--oobi', '-o', help='OOBI to use for resolving the DID', required=False)
parser.add_argument(
    '--meta',
    '-m',
    help='Whether to include metadata or only return the DID document',
    action='store_true',
    required=False,
    default=False,
)
parser.add_argument(
    '-v',
    '--verbose',
    action='store_true',
    required=False,
    default=False,
    help='Show the verbose output of DID resolution',
)
parser.add_argument(
    '--loglevel',
    action='store',
    required=False,
    default='CRITICAL',
    help='Set log level to DEBUG | INFO | WARNING | ERROR | CRITICAL. Default is CRITICAL',
)

logger = ogler.getLogger(log_name)


def handler(args):
    """Handles command line did:keri DID doc resolutions"""
    set_log_level(args.loglevel, logger)
    hby = existing.setupHby(name=args.name, base=args.base, bran=args.bran)
    hby_doer = habbing.HaberyDoer(habery=hby)  # setup doer
    oobiery = oobiing.Oobiery(hby=hby)
    res = KeriResolver(
        hby=hby, hby_doer=hby_doer, oobiery=oobiery, did=args.did, oobi=args.oobi, meta=args.meta, verbose=args.verbose
    )
    return [res]


class KeriResolver(doing.DoDoer):
    """Resolve did:keri DID document from the KEL retrieved during OOBI resolution of the provided OOBI."""

    def __init__(
        self, hby: habbing.Habery, hby_doer: Doer, oobiery: oobiing.Oobiery, did: str, oobi: str, meta: bool, verbose: bool
    ):
        self.hby: habbing.Habery = hby
        self.did: str = did
        self.oobi: str = oobi
        self.meta: bool = meta
        self.verbose = verbose

        self.result: dict = {}
        self.toRemove: List[Doer] = [
            hby_doer,
            doing.doify(self.resolve, hby=hby, did=did, oobi=oobi, meta=meta),
        ] + oobiery.doers
        doers = list(self.toRemove)
        super(KeriResolver, self).__init__(doers=doers)

    def resolve(self, hby: habbing.Habery, did: str, oobi: str, meta: bool, tock=0.0, tymth=None):
        """
        Resolve the did:keri DID document by retrieving the KEL from the OOBI resolution.
        """
        aid = didding.parse_did_keri(did)
        obr = basing.OobiRecord(date=helping.nowIso8601())
        obr.cid = aid
        hby.db.oobis.pin(keys=(oobi,), val=obr)

        while hby.db.roobi.get(keys=(oobi,)) is None:
            _ = yield tock
        try:
            self.result = didding.generate_did_doc(hby, did=did, aid=aid, oobi=oobi, meta=meta)
            if self.verbose:
                print(f'Resolution result for did:keri DID {self.did}:\n{json.dumps(self.result, indent=2)}')
            logger.info(f'did:keri Resolution result: {json.dumps(self.result, indent=2)}')
            print(f'Verification success for did:keri DID: {self.did}')
        except Exception as ex:
            logger.error(f'Error resolving did:keri DID: {did} with OOBI {oobi}: {ex}')
            print(f'Verification failure for did:keri DID: {did} with OOBI {oobi}: {ex}')
            self.result = {'error': str(ex)}
            return
        else:
            self.remove(self.toRemove)

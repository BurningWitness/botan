{-|
Module      : Botan.Low.ElGamal
Description : Algorithm specific key operations: ElGamal
Copyright   : (c) Leo D, 2023
License     : BSD-3-Clause
Maintainer  : leo@apotheca.io
Stability   : experimental
Portability : POSIX
-}

module Botan.Low.PubKey.ElGamal where

import qualified Data.ByteString as ByteString

import Botan.Bindings.PubKey
import Botan.Bindings.PubKey.ElGamal

import Botan.Low.Error
import Botan.Low.Make
import Botan.Low.MPI
import Botan.Low.Prelude
import Botan.Low.PubKey
import Botan.Low.RNG

-- /*
-- * Algorithm specific key operations: ElGamal
-- */

privKeyCreateElGamalIO :: RNGCtx -> Int -> Int -> IO PrivKey
privKeyCreateElGamalIO rng pbits qbits = withRNGPtr rng $ \ rngPtr -> do
    alloca $ \ outPtr -> do
        throwBotanIfNegative_ $ botan_privkey_create_elgamal outPtr rngPtr (fromIntegral pbits) (fromIntegral qbits)
        out <- peek outPtr
        foreignPtr <- newForeignPtr botan_privkey_destroy out
        return $ MkPrivKey foreignPtr

privKeyLoadElGamalIO :: MP -> MP -> MP -> IO PrivKey
privKeyLoadElGamalIO = mkPrivKeyLoad3 botan_privkey_load_elgamal

pubKeyLoadElGamalIO :: MP -> MP -> MP -> IO PubKey
pubKeyLoadElGamalIO = mkPubKeyLoad3 botan_pubkey_load_elgamal

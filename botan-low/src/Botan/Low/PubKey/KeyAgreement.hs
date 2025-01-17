{-|
Module      : Botan.Low.KeyAgreement
Description : Key Agreement
Copyright   : (c) Leo D, 2023
License     : BSD-3-Clause
Maintainer  : leo@apotheca.io
Stability   : experimental
Portability : POSIX
-}

module Botan.Low.PubKey.KeyAgreement where

import qualified Data.ByteString as ByteString

import Botan.Bindings.PubKey.KeyAgreement

import Botan.Low.Error
import Botan.Low.KDF
import Botan.Low.Make
import Botan.Low.Prelude
import Botan.Low.PubKey

-- /*
-- * Key Agreement
-- */

newtype KeyAgreementCtx = MkKeyAgreementCtx { getKeyAgreementForeignPtr :: ForeignPtr KeyAgreementStruct }

withKeyAgreementPtr :: KeyAgreementCtx -> (KeyAgreementPtr -> IO a) -> IO a
withKeyAgreementPtr = withForeignPtr . getKeyAgreementForeignPtr

keyAgreementCtxCreateIO :: PrivKey -> KDFName -> IO KeyAgreementCtx
keyAgreementCtxCreateIO sk algo = alloca $ \ outPtr -> do
    withPrivKeyPtr sk $ \ skPtr -> do
        asCString algo $ \ algoPtr -> do
            throwBotanIfNegative_ $ botan_pk_op_key_agreement_create
                outPtr
                skPtr
                algoPtr
                0
            out <- peek outPtr
            foreignPtr <- newForeignPtr botan_pk_op_key_agreement_destroy out
            return $ MkKeyAgreementCtx foreignPtr

keyAgreementCtxDestroyIO :: KeyAgreementCtx -> IO ()
keyAgreementCtxDestroyIO ka = finalizeForeignPtr (getKeyAgreementForeignPtr ka)

withKeyAgreementCtxCreateIO :: PrivKey -> KDFName -> (KeyAgreementCtx -> IO a) -> IO a
withKeyAgreementCtxCreateIO = mkWithTemp2 keyAgreementCtxCreateIO keyAgreementCtxDestroyIO

-- NOTE: I do not know if this provides a different functionality than just being
--  an alias for botan_privkey_export_pubkey / privKeyExportPubKeyIO
--  Observe that it *does* just take a privkey, instead of a keyagreement
--  It may simply be here for convenience.
{-
int botan_pk_op_key_agreement_export_public(botan_privkey_t key, uint8_t out[], size_t* out_len) {
   return copy_view_bin(out, out_len, botan_pk_op_key_agreement_view_public, key);
}

int botan_pk_op_key_agreement_view_public(botan_privkey_t key, botan_view_ctx ctx, botan_view_bin_fn view) {
   return BOTAN_FFI_VISIT(key, [=](const auto& k) -> int {
      if(auto kak = dynamic_cast<const Botan::PK_Key_Agreement_Key*>(&k))
         return invoke_view_callback(view, ctx, kak->public_value());
      else
         return BOTAN_FFI_ERROR_INVALID_INPUT;
   });
}
-}
keyAgreementExportPublicIO :: PrivKey -> IO ByteString
keyAgreementExportPublicIO sk = withPrivKeyPtr sk $ \ skPtr -> do
    allocBytesQuerying $ \ outPtr outLen -> botan_pk_op_key_agreement_export_public
        skPtr
        outPtr
        outLen

keyAgreementCtxSizeIO :: KeyAgreementCtx -> IO Int
keyAgreementCtxSizeIO = mkGetSize withKeyAgreementPtr botan_pk_op_key_agreement_size

keyAgreementIO :: KeyAgreementCtx -> ByteString -> ByteString -> IO ByteString
keyAgreementIO ka key salt = withKeyAgreementPtr ka $ \ kaPtr -> do
    asBytesLen key $ \ keyPtr keyLen -> do
        asBytesLen salt $ \ saltPtr saltLen -> do
            allocBytesQuerying $ \ outPtr outLen -> botan_pk_op_key_agreement
                kaPtr
                outPtr
                outLen
                keyPtr
                keyLen
                saltPtr
                saltLen

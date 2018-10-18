-- MIT License
--
-- Copyright (c) 2018 Christian Klinger
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

module ADiff.Verifier.Smack (smack) where

import           ADiff.Prelude
import           ADiff.Verifier.Util

import           System.Process

smack = Verifier "smack" executeSmack versionSmack

executeSmack :: FilePath -> RIO VerifierEnv VerifierResult
executeSmack fp =
  withSystemTempDirectory "smack" $ \dir -> do
    let cmd = shell $ "cd " ++ dir ++ "; " ++ "CORRAL=\"mono /tmp/corral/bin/Release/corral.exe\" smack -x=svcomp --clang-options=-m32 --unroll 1000 --loop-limit 1000 "  ++ fp
    withTiming cmd "" $ \ec _ _ ->
      case ec of
        ExitFailure _ -> return Sat
        ExitSuccess -> return Unsat

versionSmack = undefined

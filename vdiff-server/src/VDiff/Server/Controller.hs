{-# LANGUAGE AllowAmbiguousTypes       #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE PartialTypeSignatures     #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TypeFamilies              #-}

module VDiff.Server.Controller where

import           VDiff.Server.Prelude
import           VDiff.Server.Widgets

import qualified Control.Concurrent.MSemN              as Sema
import           Data.FileEmbed
import           Data.List
import qualified Data.Map                              as Map
import           Data.Semigroup
import qualified Data.Text                             as T
import qualified Data.Text.IO                          as T
import qualified Data.Text.Lazy                        as LT
import           Database.Beam
import           Database.Beam.Sqlite
import           Network.Wai.Middleware.StaticEmbedded
import           Numeric
import           VDiff.Data
import           VDiff.Persistence
import qualified VDiff.Query2                          as Q2
import           VDiff.Statistics
import           VDiff.Verifier                        (allVerifiers,
                                                        lookupVerifier)


endpoints :: (HasLogFunc env, HasSemaphore env, HasDatabase env) => ScottyT SrvError (RIO env) ()
endpoints = do
  get "/" getIndex
  get "/overview" getOverview
  get "/program/:hash" getProgram
  get "/findings/" getFindings
  get "/scratchpad" getScratch
  post "/run-verifier" postRunVerifier

  -- install static middleware
  middleware (static $(embedDir "static"))




getIndex :: (HasDatabase env) => RioActionM env ()
getIndex = do
  statistics <- lift Q2.stats
  defaultLayout "VDiff " $(shamletFile "templates/index.hamlet")

-- | shows all runs on one instrumented file
getProgram :: (HasDatabase env) => RioActionM env ()
getProgram = do
  hash <- param "hash"
  (runs_ :: [VerifierRun]) <- lift $ runBeam $ runSelectReturningList $ select $ Q2.runsByHash hash
  let runs = groupRuns runs_
  (Just program) <- lift $ Q2.programByHash hash
  tags <- lift $ Q2.tagsForProgram hash
  defaultLayout ("program: " <> hash) $(shamletFile "templates/program.hamlet")

data VerifierRunAggregate = VerifierRunAggregate
  { raName       :: Text
  , raVerdict    :: Verdict
  , raTime       :: (Double, Double)
  , raMemory     :: (Int, Int)
  , raOccurences :: Int
  }

groupRuns :: [VerifierRun] -> [VerifierRunAggregate]
groupRuns = map aggregate . groupBy sameNameAndVerdict . sortOn verdictAndName
  where
    sameNameAndVerdict r1 r2 = verdictAndName r1 == verdictAndName r2
    aggregate l@(r:rs) = VerifierRunAggregate (r ^. verifierName) (r ^. (result . verdict)) (0,0) (0,0) (length l)
    verdictAndName r = (show (r ^. (result . verdict)), r ^. verifierName)


-- getQueries :: RioActionM env ()
  -- getQueries = do
--   defaultLayout "Queries" $(shamletFile "templates/queries.hamlet")

getFindings :: (HasDatabase env) => RioActionM env ()
getFindings = do
  (qstring :: Text) <- param "q"
  (q :: Q2.Query) <- param "q"
  (page :: Integer) <- param "page" `rescue` const (return 1)
  (qf :: Q2.QueryFocus) <- param "qf" `rescue` const (return $ Q2.QueryFocus verifierNames)
  (qfstring :: Text) <- param "qf" `rescue` const (return $ tshow verifierNames)
  let pageSize = 30
  let offset = (page - 1) * 30
  countFindings <- lift $ Q2.executeQueryCount qf q
  findings <- lift $ Q2.executeQuery pageSize offset qf q
  pg <- mkPaginationWidget 30 countFindings (fromIntegral page) qstring qfstring
  defaultLayout "Findings" $(shamletFile "templates/findings.hamlet")

instance Parsable Q2.Query where
    parseParam = mapLeft LT.fromStrict . Q2.parseQuery . LT.toStrict

instance Parsable Q2.QueryFocus where
 parseParam p = case readMay (LT.unpack p) of
                  Nothing -> Left "xx"
                  Just vs -> Right $ Q2.QueryFocus vs

verifierNames = map (^. name) allVerifiers


getScratch ::  (HasDatabase env) => RioActionM env ()
getScratch = do
  -- if this param is set, load the source from the database
  pid <- paramMay "program"
  code <- case pid of
    Nothing -> return "int main(){...}" -- TODO add default stuff
    Just pid -> do
      (Just p) <- lift $ Q2.programByHash pid
      return $ p ^. source

  defaultLayout "Scratchpad" $(shamletFile "templates/scratchpad.hamlet")

postRunVerifier :: (HasLogFunc env, HasSemaphore env) => RioActionM env ()
postRunVerifier = do
  source <- param "source"
  timeout <- (*1000000) . read <$> param "timeout"
  (Just v) <- lookupVerifier <$> param "verifier"

  sema <- lift $ view semaphore
  -- execute verifier here inside a semaphore-protected area
  res <- lift $ with' sema 1 $ withSystemTempFile "program.c" $ \fp h -> do
    liftIO $ T.hPutStr h source >> hFlush h
    venv <- mkVerifierEnv timeout []
    runRIO venv $ execute v fp

  html $ LT.fromStrict $ tshow (res ^. verdict)

getOverview :: (HasDatabase env) => RioActionM env ()
getOverview = do
  soundnessTbl    <- lift $ overPairs relativeSoundness
  completenessTbl <- lift $ overPairs relativeCompleteness
  recallTbl       <- lift $ overPairs relativeRecall
  precisionTbl    <- lift $ overPairs relativePrecision

  defaultLayout "Overview" $(shamletFile "templates/overview.hamlet")
  where
    mkUnsoundnessLink, mkIncompletenessLink :: VerifierName -> VerifierName -> Text
    mkUnsoundnessLink v1 v2 = "/findings?q=Query SuspicionUnsound (AnyOf [%22"<> v2 <> "%22])&qf=[%22" <> v1 <> "%22]"
    mkIncompletenessLink v1 v2 = "/findings?q=Query SuspicionIncomplete (AnyOf [%22"<> v2 <> "%22])&qf=[%22" <> v1 <> "%22]"
    mkPrecisionLink _ _ = "#"
    mkRecallLink _ _ = "#"

--------------------------------------------------------------------------------
with' :: (Integral i, MonadUnliftIO m, MonadIO m) => Sema.MSemN i -> i -> m a -> m a
with' sem i a = do
  env <- askUnliftIO
  liftIO $ Sema.with sem i $ unliftIO env a

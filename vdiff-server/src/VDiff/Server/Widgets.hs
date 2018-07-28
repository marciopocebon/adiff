{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TemplateHaskell   #-}

module VDiff.Server.Widgets where

import qualified Data.List            as L
import qualified Data.Map             as Map
import qualified Data.Text            as T
import qualified Data.Text.Lazy       as LT
import           VDiff.Server.Prelude

import           VDiff.Data
import qualified VDiff.Query2         as Q2
import           VDiff.Verifier       (allVerifiers)

mkProgramLink :: ProgramId -> Html
mkProgramLink pid =
  let trunc = T.take 5 hsh
      hsh = programIdToHash pid
  in [shamlet| <a href="/program/#{hsh}">#{trunc}|]



mkPaginationWidget :: Int -> Int -> Int -> RioActionM env Html
mkPaginationWidget pageSize totalCount page = do
  let numPages = totalCount `div` pageSize
      totalLinks = 10
      pref = [max (page - 5) 1 .. page - 1]
      pages = pref ++ [page .. min (page + ((totalLinks - 1) - length pref)) numPages]
      showLeftArr = if page > 1 then "" else "disabled" :: Text
      showRightArr = if page < numPages then "" else "disabled" :: Text
      prevPage = page - 1
      nextPage = page + 1
  return $(shamletFile "templates/widgets/pagination.hamlet")


correlationTable :: Map (Relatee, Relatee) (Integer, Integer)
  -> (Relatee -> Relatee -> LT.Text)
  -> Html
correlationTable tbl mkLink = do
  let verifierNames  = (L.nub $ map fst $ Map.keys tbl) :: [Relatee]
  $(shamletFile "templates/widgets/correlationTable.hamlet")

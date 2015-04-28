module Evaluator where

import Control.Concurrent.STM
import Control.Monad
import System.Environment

import Parser

type Environment = TVar ( [(Identifier, TVar Type)]
                        , [(Identifier, TVar Expression)]
                        )

newEnvironment :: STM (Environment)
newEnvironment = newTVar ([], [])

newEnvironmentIO :: IO (Environment)
newEnvironmentIO = newTVarIO ([], [])

showEnv :: Environment -> STM (String)
showEnv env = do
    (_, varList) <- readTVar env
    liftM concat $ forM varList $ \(i, et) -> do
                       e <- readTVar et
                       t <- getType env i
                       return $    i
                                ++ ": "
                                ++ (show e)
                                ++ " ("
                                ++ (show t)
                                ++ ")\n"

setVariable :: Environment -> Identifier -> Expression -> STM ()
setVariable env i e = do (typeList, varList) <- readTVar env
                         case (lookup i varList) of
                             Nothing -> do et <- newTVar e
                                           writeTVar env ( typeList
                                                         , (i, et) : varList
                                                         )
                             Just et -> writeTVar et e

getVariable :: Environment -> Identifier -> STM (Expression)
getVariable env i = do (typeList, varList) <- readTVar env
                       case (lookup i varList) of
                           Nothing -> error $ "[TODO] ERROR! Variable not found: "
                                              ++ (show i)
                           Just t  -> readTVar t

setType :: Environment -> Identifier -> Type -> STM ()
setType env i t = do (typeList, varList) <- readTVar env
                     case (lookup i typeList) of
                         Nothing -> do tt <- newTVar t
                                       writeTVar env ( (i, tt) : typeList
                                                     , varList
                                                     )
                         Just tt -> writeTVar tt t

getType :: Environment -> Identifier -> STM (Type)
getType env i = do (typeList, _) <- readTVar env
                   case (lookup i typeList) of
                       Nothing -> error $ "[TODO] ERROR! Type not found: " ++ (show i)
                       Just t  -> readTVar t

resolveType :: Environment -> Expression -> STM (Type)
resolveType env NothingExpression = return NothingType
resolveType env (IntegerExpression _) = return IntegerType
resolveType env (StringExpression _) = return StringType
resolveType env (BooleanExpression _) = return BooleanType
-- resolveType env (IfExpression _ a b) -- Either a b [TODO] OptionType
resolveType env (LambdaExpression _ e) = resolveType env e
resolveType env (RetExpression e) = resolveType env e
resolveType env (TypeDeclarationExpression _ _) = return NothingType
resolveType env (FCallExpression i _) = getType env i
resolveType env (AssignmentExpression i e) = getType env i
resolveType env (VariableExpression i) = getType env i

newScope :: Environment -> [TypedIdentifier] -> [Expression] -> STM (Environment)
newScope oldEnv typedIdentifiers es = do
    (typeList, varList) <- readTVar oldEnv
    newEnv <- newEnvironment
    forM_ typeList $ \(i, tt) -> do
        t <- readTVar tt
        setType newEnv i t
    forM_ varList $ \(i, et) -> do
        e <- readTVar et
        setVariable newEnv i e
    zipWithM_ (setup newEnv) typedIdentifiers es
    return newEnv
  where
    setup env (TypedIdentifier i t) e = do setType env i t
                                           setVariable env i e

eval :: Environment -> Expression -> IO (Expression)
eval env NothingExpression = return NothingExpression
eval env (BlockExpression t b) = do
    newEnv <- atomically $ newScope env [] []
    foldM (foldEval newEnv) NothingExpression b
  where
    foldEval blockEnv result expr = do
    if (result /= NothingExpression)
        then do
            return result
        else do
            r <- eval blockEnv expr
            case r of
                RetExpression e -> eval blockEnv e
                otherwise       -> return result
eval env val@(IntegerExpression _) = return val
eval env val@(StringExpression _) = return val
eval env val@(BooleanExpression _) = return val
eval env (IfExpression condition truePath falsePath) = do
    (BooleanExpression success) <- eval env condition
    let path = if success then truePath else falsePath
    eval env path
eval env val@(LambdaExpression params expressions) = return val
eval env val@(RetExpression _) = return val
eval env val@(TypeDeclarationExpression i t) = do atomically $ setType env i t
                                                  return NothingExpression
eval env (FCallExpression "neg" [e]) =
    eval env e >>= return . negInteger
eval env (FCallExpression "pred" [e]) =
    eval env e >>= return . predInteger
eval env (FCallExpression "succ" [e]) =
    eval env e >>= return . succInteger
eval env (FCallExpression "add" es) =
    mapM (eval env) es >>= return . foldInteger (+)
eval env (FCallExpression "mul" es) =
    mapM (eval env) es >>= return . foldInteger (*)
eval env (FCallExpression "eq" es) =
    mapM (eval env) es >>= return . allExpression (==)
eval env (FCallExpression "lt" es) =
    mapM (eval env) es >>= return . allExpression (<)
eval env (FCallExpression "lte" es) =
    mapM (eval env) es >>= return . allExpression (<=)
eval env (FCallExpression "gt" es) =
    mapM (eval env) es >>= return . allExpression (>)
eval env (FCallExpression "gte" es) =
    mapM (eval env) es >>= return . allExpression (>=)
eval env (FCallExpression "print" [e]) =
    eval env e >>= print >> return NothingExpression
eval env (FCallExpression "env" []) =
    (atomically . showEnv) env >>= return . StringExpression
eval env (FCallExpression name args) = do
    f@(LambdaExpression params body) <- atomically $ getVariable env name
    evaluatedArgs <- mapM (eval env) args
    newEnv <- atomically $ newScope env params evaluatedArgs
    eval newEnv body
eval env (AssignmentExpression i e) = do newE <- eval env e
                                         atomically $ setVariable env i newE
                                         return newE
eval env (VariableExpression i) = atomically $ getVariable env i

-- Builtins

negInteger :: Expression -> Expression
negInteger (IntegerExpression n) = IntegerExpression (-n)

predInteger :: Expression -> Expression
predInteger (IntegerExpression n) = IntegerExpression (n - 1)

succInteger :: Expression -> Expression
succInteger (IntegerExpression n) = IntegerExpression (n + 1)

foldInteger :: (Integer -> Integer -> Integer) -> [Expression] -> Expression
foldInteger f = foldl1 $ \(IntegerExpression a) (IntegerExpression n) ->
                             IntegerExpression (f a n)

allExpression :: (Expression -> Expression -> Bool) ->
                 [Expression] -> Expression
allExpression f (e:es) = BooleanExpression $ all (\x -> f e x) es

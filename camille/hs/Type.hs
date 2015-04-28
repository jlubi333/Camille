module Type where

import Control.Monad.Error

type Identifier = String

data Type = NothingType
          | IntegerType
          | StringType
          | BooleanType
          deriving (Eq, Show)

data TypedIdentifier = TypedIdentifier Identifier Type
                     deriving (Eq)

data Expression = NothingExpression
                | BlockExpression Type [Expression]
                | IntegerExpression Integer
                | StringExpression String
                | BooleanExpression Bool
                | IfExpression Expression Expression Expression
                | LambdaExpression [TypedIdentifier] Expression
                | RetExpression Expression
                | TypeDeclarationExpression Identifier Type
                | FCallExpression Identifier [Expression]
                | AssignmentExpression Identifier Expression
                | VariableExpression Identifier
                deriving (Eq)
instance Ord Expression where
    compare NothingExpression _                         = LT
    compare (IntegerExpression a) (IntegerExpression b) = compare a b
    compare (StringExpression a) (StringExpression b)   = compare a b
    compare (BooleanExpression a) (BooleanExpression b) = compare a b
    compare _ _                                         = EQ
instance Show Expression where
    show NothingExpression               = "Nothing"
    show (BlockExpression _ _)           = "<block>"
    show (IntegerExpression i)           = show i
    show (StringExpression s)            = s
    show (BooleanExpression b)           = show b
    show (IfExpression _ _ _)            = "<if>"
    show (LambdaExpression _ _)        = "<lambda>"
    show (RetExpression e)               = "Ret (" ++ (show e) ++ ")"
    show (TypeDeclarationExpression _ _) = "<type-declaration>"
    show (FCallExpression _ _)           = "<fcall>"
    show (AssignmentExpression _ _)      = "<assignment>"
    show (VariableExpression i)          = "Var \"" ++ i ++ "\""

data LanguageError = TypeMismatchError
                   | NoSuchVariableError
                   | GenericError String
instance Error LanguageError where
    noMsg  = GenericError "An error has occurred."
    strMsg = GenericError

type IOThrowsError = ErrorT LanguageError IO
import os
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, Response, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import delete
from sqlalchemy.orm import Session

from . import apple, auth, billing, sync
from .database import engine, get_db
from .models import Base, User
from .schemas import Profile, profile_of
from .seed import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    init_db(engine)
    yield


app = FastAPI(title="Toa API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
        if origin.strip()
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(sync.router)
app.include_router(billing.router)
app.include_router(apple.router)

DbSession = Annotated[Session, Depends(get_db)]


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/me", response_model=Profile)
def read_me(user: auth.CurrentUser):
    return profile_of(user)


@app.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(user: auth.CurrentUser, db: DbSession):
    # Every user table cascades on users.id
    db.execute(delete(User.__table__).where(User.__table__.c.id == user.id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

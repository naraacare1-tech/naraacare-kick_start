"""Shared route dependencies: the services built at start-up (``app.main._init_state``)."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request

from app.domain.ai.rin_service import RinService
from app.domain.auth.service import AuthService
from app.domain.billing.service import BillingService
from app.domain.entitlements.service import EntitlementService
from app.domain.hydration.service import HydrationService
from app.domain.notifications.service import NotificationService
from app.domain.nutrition.service import NutritionService
from app.domain.privacy.service import PrivacyService
from app.domain.profile.service import ProfileService
from app.domain.reference import ReferenceCache
from app.domain.referral.service import ReferralService
from app.domain.reports.service import ReportService
from app.domain.sleep.service import SleepService
from app.domain.social.service import SocialService
from app.domain.support.service import SupportService
from app.domain.sync.service import SyncService


def get_auth_service(request: Request) -> AuthService:
    service: AuthService = request.app.state.auth_service
    return service


def get_profile_service(request: Request) -> ProfileService:
    service: ProfileService = request.app.state.profile_service
    return service


def get_reference(request: Request) -> ReferenceCache:
    reference: ReferenceCache = request.app.state.reference
    return reference


def get_entitlements(request: Request) -> EntitlementService:
    service: EntitlementService = request.app.state.entitlements
    return service


def get_nutrition_service(request: Request) -> NutritionService:
    service: NutritionService = request.app.state.nutrition_service
    return service


def get_hydration_service(request: Request) -> HydrationService:
    service: HydrationService = request.app.state.hydration_service
    return service


def get_notification_service(request: Request) -> NotificationService:
    service: NotificationService = request.app.state.notification_service
    return service


def get_sleep_service(request: Request) -> SleepService:
    service: SleepService = request.app.state.sleep_service
    return service


def get_billing_service(request: Request) -> BillingService:
    service: BillingService = request.app.state.billing_service
    return service


def get_referral_service(request: Request) -> ReferralService:
    service: ReferralService = request.app.state.referral_service
    return service


def get_social_service(request: Request) -> SocialService:
    service: SocialService = request.app.state.social_service
    return service


def get_rin_service(request: Request) -> RinService:
    service: RinService = request.app.state.rin_service
    return service


def get_report_service(request: Request) -> ReportService:
    service: ReportService = request.app.state.report_service
    return service


def get_support_service(request: Request) -> SupportService:
    service: SupportService = request.app.state.support_service
    return service


def get_sync_service(request: Request) -> SyncService:
    service: SyncService = request.app.state.sync_service
    return service


def get_privacy_service(request: Request) -> PrivacyService:
    service: PrivacyService = request.app.state.privacy_service
    return service


AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]
ProfileServiceDep = Annotated[ProfileService, Depends(get_profile_service)]
ReferenceDep = Annotated[ReferenceCache, Depends(get_reference)]
EntitlementsDep = Annotated[EntitlementService, Depends(get_entitlements)]
NutritionServiceDep = Annotated[NutritionService, Depends(get_nutrition_service)]
HydrationServiceDep = Annotated[HydrationService, Depends(get_hydration_service)]
NotificationServiceDep = Annotated[NotificationService, Depends(get_notification_service)]
SleepServiceDep = Annotated[SleepService, Depends(get_sleep_service)]
BillingServiceDep = Annotated[BillingService, Depends(get_billing_service)]
ReferralServiceDep = Annotated[ReferralService, Depends(get_referral_service)]
SocialServiceDep = Annotated[SocialService, Depends(get_social_service)]
RinServiceDep = Annotated[RinService, Depends(get_rin_service)]
ReportServiceDep = Annotated[ReportService, Depends(get_report_service)]
SupportServiceDep = Annotated[SupportService, Depends(get_support_service)]
SyncServiceDep = Annotated[SyncService, Depends(get_sync_service)]
PrivacyServiceDep = Annotated[PrivacyService, Depends(get_privacy_service)]

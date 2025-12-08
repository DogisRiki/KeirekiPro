package com.example.keirekipro.unit.infrastructure.repository.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.helper.ResumeObjectBuilder;
import com.example.keirekipro.infrastructure.repository.resume.MyBatisResumeRepository;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.CareerDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.CertificationDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.PortfolioDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.ProjectDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.SelfPromotionDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.SocialLinkDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MyBatisResumeRepositoryTest {

    @Mock
    private ResumeMapper mapper;

    @InjectMocks
    private MyBatisResumeRepository repository;

    private static final UUID USER_ID = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID RESUME_ID = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static final String RESUME_NAME = "Test Resume";
    private static final LocalDate DATE = LocalDate.of(2025, 1, 1);
    private static final String LAST_NAME = "Last";
    private static final String FIRST_NAME = "First";
    private static final LocalDateTime CREATED_AT = LocalDateTime.of(2025, 1, 2, 3, 4);
    private static final LocalDateTime UPDATED_AT = LocalDateTime.of(2025, 1, 3, 4, 5);

    @Test
    @DisplayName("findAll_該当ユーザーに職務経歴書が存在しない場合、空リストが返る")
    void test1() {
        when(mapper.selectAllByUserId(USER_ID)).thenReturn(Collections.emptyList());
        List<Resume> list = repository.findAll(USER_ID);
        assertThat(list).isEmpty();
        verify(mapper).selectAllByUserId(USER_ID);
    }

    @Test
    @DisplayName("findAll_職務経歴書が存在する場合、DTOの全フィールドがエンティティに変換されて返る")
    void test2() {
        // モック設定
        ResumeDto dto = ResumeObjectBuilder.buildResumeDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        when(mapper.selectAllByUserId(USER_ID)).thenReturn(List.of(dto));
        when(mapper.selectCareersByResumeId(RESUME_ID)).thenReturn(dto.getCareers());
        when(mapper.selectProjectsByResumeId(RESUME_ID)).thenReturn(dto.getProjects());
        when(mapper.selectCertificationsByResumeId(RESUME_ID)).thenReturn(dto.getCertifications());
        when(mapper.selectPortfoliosByResumeId(RESUME_ID)).thenReturn(dto.getPortfolios());
        when(mapper.selectSocialLinksByResumeId(RESUME_ID)).thenReturn(dto.getSocialLinks());
        when(mapper.selectSelfPromotionsByResumeId(RESUME_ID)).thenReturn(dto.getSelfPromotions());

        // 実行
        List<Resume> list = repository.findAll(USER_ID);

        // 親フィールドの検証
        assertThat(list).hasSize(1);
        Resume r = list.get(0);
        assertThat(r.getId()).isEqualTo(dto.getId());
        assertThat(r.getUserId()).isEqualTo(dto.getUserId());
        assertThat(r.getName().getValue()).isEqualTo(dto.getName());
        assertThat(r.getDate()).isEqualTo(dto.getDate());
        assertThat(r.getFullName().getLastName()).isEqualTo(dto.getLastName());
        assertThat(r.getFullName().getFirstName()).isEqualTo(dto.getFirstName());
        assertThat(r.getCreatedAt()).isEqualTo(dto.getCreatedAt());
        assertThat(r.getUpdatedAt()).isEqualTo(dto.getUpdatedAt());

        // Careerの検証
        assertThat(r.getCareers()).hasSize(1);
        Career c = r.getCareers().get(0);
        CareerDto cd = dto.getCareers().get(0);
        assertThat(c.getId()).isEqualTo(cd.getId());
        assertThat(c.getCompanyName().getValue()).isEqualTo(cd.getCompanyName());
        assertThat(c.getPeriod().getStartDate()).isEqualTo(cd.getStartDate());
        assertThat(c.getPeriod().getEndDate()).isEqualTo(cd.getEndDate());
        assertThat(c.getPeriod().isActive()).isEqualTo(cd.getIsActive());

        // Projectの検証
        assertThat(r.getProjects()).hasSize(1);
        Project p = r.getProjects().get(0);
        ProjectDto pd = dto.getProjects().get(0);
        assertThat(p.getId()).isEqualTo(pd.getId());
        assertThat(p.getCompanyName().getValue()).isEqualTo(pd.getCompanyName());
        assertThat(p.getPeriod().getStartDate()).isEqualTo(pd.getStartDate());
        assertThat(p.getPeriod().getEndDate()).isEqualTo(pd.getEndDate());
        assertThat(p.getPeriod().isActive()).isEqualTo(pd.getIsActive());
        assertThat(p.getName()).isEqualTo(pd.getName());
        assertThat(p.getOverview()).isEqualTo(pd.getOverview());
        assertThat(p.getTeamComp()).isEqualTo(pd.getTeamComp());
        assertThat(p.getRole()).isEqualTo(pd.getRole());
        assertThat(p.getAchievement()).isEqualTo(pd.getAchievement());
        assertThat(p.getProcess().isRequirements()).isEqualTo(pd.getRequirements());
        assertThat(p.getProcess().isBasicDesign()).isEqualTo(pd.getBasicDesign());
        assertThat(p.getProcess().isDetailedDesign()).isEqualTo(pd.getDetailedDesign());
        assertThat(p.getProcess().isImplementation()).isEqualTo(pd.getImplementation());
        assertThat(p.getProcess().isIntegrationTest()).isEqualTo(pd.getIntegrationTest());
        assertThat(p.getProcess().isSystemTest()).isEqualTo(pd.getSystemTest());
        assertThat(p.getProcess().isMaintenance()).isEqualTo(pd.getMaintenance());

        // TechStack - Frontend
        assertThat(p.getTechStack().getFrontend().getLanguages()).isEqualTo(pd.getFrontendLanguages());
        assertThat(p.getTechStack().getFrontend().getFrameworks()).isEqualTo(pd.getFrontendFrameworks());
        assertThat(p.getTechStack().getFrontend().getLibraries()).isEqualTo(pd.getFrontendLibraries());
        assertThat(p.getTechStack().getFrontend().getBuildTools()).isEqualTo(pd.getFrontendBuildTools());
        assertThat(p.getTechStack().getFrontend().getPackageManagers()).isEqualTo(pd.getFrontendPackageManagers());
        assertThat(p.getTechStack().getFrontend().getLinters()).isEqualTo(pd.getFrontendLinters());
        assertThat(p.getTechStack().getFrontend().getFormatters()).isEqualTo(pd.getFrontendFormatters());
        assertThat(p.getTechStack().getFrontend().getTestingTools()).isEqualTo(pd.getFrontendTestingTools());

        // TechStack - Backend
        assertThat(p.getTechStack().getBackend().getLanguages()).isEqualTo(pd.getBackendLanguages());
        assertThat(p.getTechStack().getBackend().getFrameworks()).isEqualTo(pd.getBackendFrameworks());
        assertThat(p.getTechStack().getBackend().getLibraries()).isEqualTo(pd.getBackendLibraries());
        assertThat(p.getTechStack().getBackend().getBuildTools()).isEqualTo(pd.getBackendBuildTools());
        assertThat(p.getTechStack().getBackend().getPackageManagers()).isEqualTo(pd.getBackendPackageManagers());
        assertThat(p.getTechStack().getBackend().getLinters()).isEqualTo(pd.getBackendLinters());
        assertThat(p.getTechStack().getBackend().getFormatters()).isEqualTo(pd.getBackendFormatters());
        assertThat(p.getTechStack().getBackend().getTestingTools()).isEqualTo(pd.getBackendTestingTools());
        assertThat(p.getTechStack().getBackend().getOrmTools()).isEqualTo(pd.getOrmTools());
        assertThat(p.getTechStack().getBackend().getAuth()).isEqualTo(pd.getAuth());

        // TechStack - Infrastructure
        assertThat(p.getTechStack().getInfrastructure().getClouds()).isEqualTo(pd.getClouds());
        assertThat(p.getTechStack().getInfrastructure().getOperatingSystems()).isEqualTo(pd.getOperatingSystems());
        assertThat(p.getTechStack().getInfrastructure().getContainers()).isEqualTo(pd.getContainers());
        assertThat(p.getTechStack().getInfrastructure().getDatabases()).isEqualTo(pd.getDatabases());
        assertThat(p.getTechStack().getInfrastructure().getWebServers()).isEqualTo(pd.getWebServers());
        assertThat(p.getTechStack().getInfrastructure().getCiCdTools()).isEqualTo(pd.getCiCdTools());
        assertThat(p.getTechStack().getInfrastructure().getIacTools()).isEqualTo(pd.getIacTools());
        assertThat(p.getTechStack().getInfrastructure().getMonitoringTools()).isEqualTo(pd.getMonitoringTools());
        assertThat(p.getTechStack().getInfrastructure().getLoggingTools()).isEqualTo(pd.getLoggingTools());

        // TechStack - Tools
        assertThat(p.getTechStack().getTools().getSourceControls()).isEqualTo(pd.getSourceControls());
        assertThat(p.getTechStack().getTools().getProjectManagements()).isEqualTo(pd.getProjectManagements());
        assertThat(p.getTechStack().getTools().getCommunicationTools()).isEqualTo(pd.getCommunicationTools());
        assertThat(p.getTechStack().getTools().getDocumentationTools()).isEqualTo(pd.getDocumentationTools());
        assertThat(p.getTechStack().getTools().getApiDevelopmentTools()).isEqualTo(pd.getApiDevelopmentTools());
        assertThat(p.getTechStack().getTools().getDesignTools()).isEqualTo(pd.getDesignTools());
        assertThat(p.getTechStack().getTools().getEditors()).isEqualTo(pd.getEditors());
        assertThat(p.getTechStack().getTools().getDevelopmentEnvironments())
                .isEqualTo(pd.getDevelopmentEnvironments());

        // Certificationの検証
        assertThat(r.getCertifications()).hasSize(1);
        Certification certEnt = r.getCertifications().get(0);
        CertificationDto certDto = dto.getCertifications().get(0);
        assertThat(certEnt.getId()).isEqualTo(certDto.getId());
        assertThat(certEnt.getName()).isEqualTo(certDto.getName());
        assertThat(certEnt.getDate()).isEqualTo(certDto.getDate());

        // Portfolioの検証
        assertThat(r.getPortfolios()).hasSize(1);
        Portfolio portEnt = r.getPortfolios().get(0);
        PortfolioDto portDto = dto.getPortfolios().get(0);
        assertThat(portEnt.getId()).isEqualTo(portDto.getId());
        assertThat(portEnt.getName()).isEqualTo(portDto.getName());
        assertThat(portEnt.getOverview()).isEqualTo(portDto.getOverview());
        assertThat(portEnt.getTechStack()).isEqualTo(portDto.getTechStack());
        assertThat(portEnt.getLink().getValue()).isEqualTo(portDto.getLink());

        // SocialLinkの検証
        assertThat(r.getSocialLinks()).hasSize(1);
        SocialLink slEnt = r.getSocialLinks().get(0);
        SocialLinkDto slDto = dto.getSocialLinks().get(0);
        assertThat(slEnt.getId()).isEqualTo(slDto.getId());
        assertThat(slEnt.getName()).isEqualTo(slDto.getName());
        assertThat(slEnt.getLink().getValue()).isEqualTo(slDto.getLink());

        // SelfPromotionの検証
        assertThat(r.getSelfPromotions()).hasSize(1);
        SelfPromotion spEnt = r.getSelfPromotions().get(0);
        SelfPromotionDto spDto = dto.getSelfPromotions().get(0);
        assertThat(spEnt.getId()).isEqualTo(spDto.getId());
        assertThat(spEnt.getTitle()).isEqualTo(spDto.getTitle());
        assertThat(spEnt.getContent()).isEqualTo(spDto.getContent());
    }

    @Test
    @DisplayName("find_職務経歴書が存在しない場合、空のOptionalが返る")
    void test3() {
        UUID rid = UUID.randomUUID();
        when(mapper.selectByResumeId(rid)).thenReturn(Optional.empty());
        Optional<Resume> opt = repository.find(rid);
        assertThat(opt).isEmpty();
        verify(mapper).selectByResumeId(rid);
    }

    @Test
    @DisplayName("find_職務経歴書が存在する場合、DTOの全フィールドがエンティティに変換されて返る")
    void test4() {
        // モック設定
        ResumeDto dto = ResumeObjectBuilder.buildResumeDto(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        when(mapper.selectByResumeId(RESUME_ID)).thenReturn(Optional.of(dto));
        when(mapper.selectCareersByResumeId(RESUME_ID)).thenReturn(dto.getCareers());
        when(mapper.selectProjectsByResumeId(RESUME_ID)).thenReturn(dto.getProjects());
        when(mapper.selectCertificationsByResumeId(RESUME_ID)).thenReturn(dto.getCertifications());
        when(mapper.selectPortfoliosByResumeId(RESUME_ID)).thenReturn(dto.getPortfolios());
        when(mapper.selectSocialLinksByResumeId(RESUME_ID)).thenReturn(dto.getSocialLinks());
        when(mapper.selectSelfPromotionsByResumeId(RESUME_ID)).thenReturn(dto.getSelfPromotions());

        // 実行
        Optional<Resume> opt = repository.find(RESUME_ID);
        assertThat(opt).isPresent();
        Resume r = opt.get();

        // 親フィールドの検証
        assertThat(r.getId()).isEqualTo(dto.getId());
        assertThat(r.getUserId()).isEqualTo(dto.getUserId());
        assertThat(r.getName().getValue()).isEqualTo(dto.getName());
        assertThat(r.getDate()).isEqualTo(dto.getDate());
        assertThat(r.getFullName().getLastName()).isEqualTo(dto.getLastName());
        assertThat(r.getFullName().getFirstName()).isEqualTo(dto.getFirstName());
        assertThat(r.getCreatedAt()).isEqualTo(dto.getCreatedAt());
        assertThat(r.getUpdatedAt()).isEqualTo(dto.getUpdatedAt());

        // Careerの検証
        assertThat(r.getCareers()).hasSize(dto.getCareers().size());
        ResumeDto.CareerDto cd = dto.getCareers().get(0);
        Career c = r.getCareers().get(0);
        assertThat(c.getId()).isEqualTo(cd.getId());
        assertThat(c.getCompanyName().getValue()).isEqualTo(cd.getCompanyName());
        assertThat(c.getPeriod().getStartDate()).isEqualTo(cd.getStartDate());
        assertThat(c.getPeriod().getEndDate()).isEqualTo(cd.getEndDate());
        assertThat(c.getPeriod().isActive()).isEqualTo(cd.getIsActive());

        // Projectの検証
        assertThat(r.getProjects()).hasSize(dto.getProjects().size());
        ResumeDto.ProjectDto pd = dto.getProjects().get(0);
        Project p = r.getProjects().get(0);
        assertThat(p.getId()).isEqualTo(pd.getId());
        assertThat(p.getCompanyName().getValue()).isEqualTo(pd.getCompanyName());
        assertThat(p.getPeriod().getStartDate()).isEqualTo(pd.getStartDate());
        assertThat(p.getPeriod().getEndDate()).isEqualTo(pd.getEndDate());
        assertThat(p.getPeriod().isActive()).isEqualTo(pd.getIsActive());
        assertThat(p.getName()).isEqualTo(pd.getName());
        assertThat(p.getOverview()).isEqualTo(pd.getOverview());
        assertThat(p.getTeamComp()).isEqualTo(pd.getTeamComp());
        assertThat(p.getRole()).isEqualTo(pd.getRole());
        assertThat(p.getAchievement()).isEqualTo(pd.getAchievement());
        // Process
        assertThat(p.getProcess().isRequirements()).isEqualTo(pd.getRequirements());
        assertThat(p.getProcess().isBasicDesign()).isEqualTo(pd.getBasicDesign());
        assertThat(p.getProcess().isDetailedDesign()).isEqualTo(pd.getDetailedDesign());
        assertThat(p.getProcess().isImplementation()).isEqualTo(pd.getImplementation());
        assertThat(p.getProcess().isIntegrationTest()).isEqualTo(pd.getIntegrationTest());
        assertThat(p.getProcess().isSystemTest()).isEqualTo(pd.getSystemTest());
        assertThat(p.getProcess().isMaintenance()).isEqualTo(pd.getMaintenance());
        // TechStack - Frontend
        assertThat(p.getTechStack().getFrontend().getLanguages()).isEqualTo(pd.getFrontendLanguages());
        assertThat(p.getTechStack().getFrontend().getFrameworks()).isEqualTo(pd.getFrontendFrameworks());
        assertThat(p.getTechStack().getFrontend().getLibraries()).isEqualTo(pd.getFrontendLibraries());
        assertThat(p.getTechStack().getFrontend().getBuildTools()).isEqualTo(pd.getFrontendBuildTools());
        assertThat(p.getTechStack().getFrontend().getPackageManagers()).isEqualTo(pd.getFrontendPackageManagers());
        assertThat(p.getTechStack().getFrontend().getLinters()).isEqualTo(pd.getFrontendLinters());
        assertThat(p.getTechStack().getFrontend().getFormatters()).isEqualTo(pd.getFrontendFormatters());
        assertThat(p.getTechStack().getFrontend().getTestingTools()).isEqualTo(pd.getFrontendTestingTools());
        // TechStack - Backend
        assertThat(p.getTechStack().getBackend().getLanguages()).isEqualTo(pd.getBackendLanguages());
        assertThat(p.getTechStack().getBackend().getFrameworks()).isEqualTo(pd.getBackendFrameworks());
        assertThat(p.getTechStack().getBackend().getLibraries()).isEqualTo(pd.getBackendLibraries());
        assertThat(p.getTechStack().getBackend().getBuildTools()).isEqualTo(pd.getBackendBuildTools());
        assertThat(p.getTechStack().getBackend().getPackageManagers()).isEqualTo(pd.getBackendPackageManagers());
        assertThat(p.getTechStack().getBackend().getLinters()).isEqualTo(pd.getBackendLinters());
        assertThat(p.getTechStack().getBackend().getFormatters()).isEqualTo(pd.getBackendFormatters());
        assertThat(p.getTechStack().getBackend().getTestingTools()).isEqualTo(pd.getBackendTestingTools());
        assertThat(p.getTechStack().getBackend().getOrmTools()).isEqualTo(pd.getOrmTools());
        assertThat(p.getTechStack().getBackend().getAuth()).isEqualTo(pd.getAuth());
        // TechStack - Infrastructure
        assertThat(p.getTechStack().getInfrastructure().getClouds()).isEqualTo(pd.getClouds());
        assertThat(p.getTechStack().getInfrastructure().getOperatingSystems()).isEqualTo(pd.getOperatingSystems());
        assertThat(p.getTechStack().getInfrastructure().getContainers()).isEqualTo(pd.getContainers());
        assertThat(p.getTechStack().getInfrastructure().getDatabases()).isEqualTo(pd.getDatabases());
        assertThat(p.getTechStack().getInfrastructure().getWebServers()).isEqualTo(pd.getWebServers());
        assertThat(p.getTechStack().getInfrastructure().getCiCdTools()).isEqualTo(pd.getCiCdTools());
        assertThat(p.getTechStack().getInfrastructure().getIacTools()).isEqualTo(pd.getIacTools());
        assertThat(p.getTechStack().getInfrastructure().getMonitoringTools()).isEqualTo(pd.getMonitoringTools());
        assertThat(p.getTechStack().getInfrastructure().getLoggingTools()).isEqualTo(pd.getLoggingTools());
        // TechStack - Tools
        assertThat(p.getTechStack().getTools().getSourceControls()).isEqualTo(pd.getSourceControls());
        assertThat(p.getTechStack().getTools().getProjectManagements()).isEqualTo(pd.getProjectManagements());
        assertThat(p.getTechStack().getTools().getCommunicationTools()).isEqualTo(pd.getCommunicationTools());
        assertThat(p.getTechStack().getTools().getDocumentationTools()).isEqualTo(pd.getDocumentationTools());
        assertThat(p.getTechStack().getTools().getApiDevelopmentTools()).isEqualTo(pd.getApiDevelopmentTools());
        assertThat(p.getTechStack().getTools().getDesignTools()).isEqualTo(pd.getDesignTools());
        assertThat(p.getTechStack().getTools().getEditors()).isEqualTo(pd.getEditors());
        assertThat(p.getTechStack().getTools().getDevelopmentEnvironments())
                .isEqualTo(pd.getDevelopmentEnvironments());

        // Certificationの検証
        assertThat(r.getCertifications()).hasSize(dto.getCertifications().size());
        ResumeDto.CertificationDto certd = dto.getCertifications().get(0);
        Certification cert = r.getCertifications().get(0);
        assertThat(cert.getId()).isEqualTo(certd.getId());
        assertThat(cert.getName()).isEqualTo(certd.getName());
        assertThat(cert.getDate()).isEqualTo(certd.getDate());

        // Portfolioの検証
        assertThat(r.getPortfolios()).hasSize(dto.getPortfolios().size());
        ResumeDto.PortfolioDto portd = dto.getPortfolios().get(0);
        Portfolio port = r.getPortfolios().get(0);
        assertThat(port.getId()).isEqualTo(portd.getId());
        assertThat(port.getName()).isEqualTo(portd.getName());
        assertThat(port.getOverview()).isEqualTo(portd.getOverview());
        assertThat(port.getTechStack()).isEqualTo(portd.getTechStack());
        assertThat(port.getLink().getValue()).isEqualTo(portd.getLink());

        // SocialLinkの検証
        assertThat(r.getSocialLinks()).hasSize(dto.getSocialLinks().size());
        ResumeDto.SocialLinkDto sld = dto.getSocialLinks().get(0);
        SocialLink sl = r.getSocialLinks().get(0);
        assertThat(sl.getId()).isEqualTo(sld.getId());
        assertThat(sl.getName()).isEqualTo(sld.getName());
        assertThat(sl.getLink().getValue()).isEqualTo(sld.getLink());

        // SelfPromotionの検証
        assertThat(r.getSelfPromotions()).hasSize(dto.getSelfPromotions().size());
        ResumeDto.SelfPromotionDto spd = dto.getSelfPromotions().get(0);
        SelfPromotion sp = r.getSelfPromotions().get(0);
        assertThat(sp.getId()).isEqualTo(spd.getId());
        assertThat(sp.getTitle()).isEqualTo(spd.getTitle());
        assertThat(sp.getContent()).isEqualTo(spd.getContent());
    }

    @Test
    @DisplayName("save_新規作成または更新時にupsertと子テーブルの削除・挿入が実行される")
    void test5() {
        // 準備
        Resume resume = ResumeObjectBuilder.buildResume(
                RESUME_ID, USER_ID, RESUME_NAME, DATE, LAST_NAME, FIRST_NAME, CREATED_AT, UPDATED_AT);
        final UUID id = resume.getId();

        // 実行
        repository.save(resume);

        // 親テーブルupsert
        ArgumentCaptor<ResumeDto> dtoCap = ArgumentCaptor.forClass(ResumeDto.class);
        verify(mapper).upsert(dtoCap.capture());
        ResumeDto dto = dtoCap.getValue();
        assertThat(dto.getId()).isEqualTo(resume.getId());
        assertThat(dto.getUserId()).isEqualTo(resume.getUserId());
        assertThat(dto.getName()).isEqualTo(resume.getName().getValue());
        assertThat(dto.getDate()).isEqualTo(resume.getDate());
        assertThat(dto.getLastName()).isEqualTo(resume.getFullName().getLastName());
        assertThat(dto.getFirstName()).isEqualTo(resume.getFullName().getFirstName());
        assertThat(dto.getCreatedAt()).isEqualTo(resume.getCreatedAt());
        assertThat(dto.getUpdatedAt()).isEqualTo(resume.getUpdatedAt());

        // 子テーブル全削除
        verify(mapper).deleteCareersByResumeId(id);
        verify(mapper).deleteProjectsByResumeId(id);
        verify(mapper).deleteCertificationsByResumeId(id);
        verify(mapper).deletePortfoliosByResumeId(id);
        verify(mapper).deleteSocialLinksByResumeId(id);
        verify(mapper).deleteSelfPromotionsByResumeId(id);

        // Careerインサート
        ArgumentCaptor<ResumeDto.CareerDto> capC = ArgumentCaptor.forClass(ResumeDto.CareerDto.class);
        verify(mapper).insertCareer(capC.capture());
        ResumeDto.CareerDto cd = capC.getValue();
        Career c = resume.getCareers().get(0);
        assertThat(cd.getId()).isEqualTo(c.getId());
        assertThat(cd.getResumeId()).isEqualTo(id);
        assertThat(cd.getCompanyName()).isEqualTo(c.getCompanyName().getValue());
        assertThat(cd.getStartDate()).isEqualTo(c.getPeriod().getStartDate());
        assertThat(cd.getEndDate()).isEqualTo(c.getPeriod().getEndDate());
        assertThat(cd.getIsActive()).isEqualTo(c.getPeriod().isActive());

        // Projectインサート
        ArgumentCaptor<ResumeDto.ProjectDto> capP = ArgumentCaptor.forClass(ResumeDto.ProjectDto.class);
        verify(mapper).insertProject(capP.capture());
        ResumeDto.ProjectDto pd = capP.getValue();
        Project p = resume.getProjects().get(0);
        assertThat(pd.getId()).isEqualTo(p.getId());
        assertThat(pd.getResumeId()).isEqualTo(id);
        assertThat(pd.getCompanyName()).isEqualTo(p.getCompanyName().getValue());
        assertThat(pd.getStartDate()).isEqualTo(p.getPeriod().getStartDate());
        assertThat(pd.getEndDate()).isEqualTo(p.getPeriod().getEndDate());
        assertThat(pd.getIsActive()).isEqualTo(p.getPeriod().isActive());
        assertThat(pd.getName()).isEqualTo(p.getName());
        assertThat(pd.getOverview()).isEqualTo(p.getOverview());
        assertThat(pd.getTeamComp()).isEqualTo(p.getTeamComp());
        assertThat(pd.getRole()).isEqualTo(p.getRole());
        assertThat(pd.getAchievement()).isEqualTo(p.getAchievement());
        assertThat(pd.getRequirements()).isEqualTo(p.getProcess().isRequirements());
        assertThat(pd.getBasicDesign()).isEqualTo(p.getProcess().isBasicDesign());
        assertThat(pd.getDetailedDesign()).isEqualTo(p.getProcess().isDetailedDesign());
        assertThat(pd.getImplementation()).isEqualTo(p.getProcess().isImplementation());
        assertThat(pd.getIntegrationTest()).isEqualTo(p.getProcess().isIntegrationTest());
        assertThat(pd.getSystemTest()).isEqualTo(p.getProcess().isSystemTest());
        assertThat(pd.getMaintenance()).isEqualTo(p.getProcess().isMaintenance());

        // TechStack - Frontend
        assertThat(pd.getFrontendLanguages()).isEqualTo(p.getTechStack().getFrontend().getLanguages());
        assertThat(pd.getFrontendFrameworks()).isEqualTo(p.getTechStack().getFrontend().getFrameworks());
        assertThat(pd.getFrontendLibraries()).isEqualTo(p.getTechStack().getFrontend().getLibraries());
        assertThat(pd.getFrontendBuildTools()).isEqualTo(p.getTechStack().getFrontend().getBuildTools());
        assertThat(pd.getFrontendPackageManagers()).isEqualTo(p.getTechStack().getFrontend().getPackageManagers());
        assertThat(pd.getFrontendLinters()).isEqualTo(p.getTechStack().getFrontend().getLinters());
        assertThat(pd.getFrontendFormatters()).isEqualTo(p.getTechStack().getFrontend().getFormatters());
        assertThat(pd.getFrontendTestingTools()).isEqualTo(p.getTechStack().getFrontend().getTestingTools());

        // TechStack - Backend
        assertThat(pd.getBackendLanguages()).isEqualTo(p.getTechStack().getBackend().getLanguages());
        assertThat(pd.getBackendFrameworks()).isEqualTo(p.getTechStack().getBackend().getFrameworks());
        assertThat(pd.getBackendLibraries()).isEqualTo(p.getTechStack().getBackend().getLibraries());
        assertThat(pd.getBackendBuildTools()).isEqualTo(p.getTechStack().getBackend().getBuildTools());
        assertThat(pd.getBackendPackageManagers()).isEqualTo(p.getTechStack().getBackend().getPackageManagers());
        assertThat(pd.getBackendLinters()).isEqualTo(p.getTechStack().getBackend().getLinters());
        assertThat(pd.getBackendFormatters()).isEqualTo(p.getTechStack().getBackend().getFormatters());
        assertThat(pd.getBackendTestingTools()).isEqualTo(p.getTechStack().getBackend().getTestingTools());
        assertThat(pd.getOrmTools()).isEqualTo(p.getTechStack().getBackend().getOrmTools());
        assertThat(pd.getAuth()).isEqualTo(p.getTechStack().getBackend().getAuth());

        // TechStack - Infrastructure
        assertThat(pd.getClouds()).isEqualTo(p.getTechStack().getInfrastructure().getClouds());
        assertThat(pd.getOperatingSystems()).isEqualTo(p.getTechStack().getInfrastructure().getOperatingSystems());
        assertThat(pd.getContainers()).isEqualTo(p.getTechStack().getInfrastructure().getContainers());
        assertThat(pd.getDatabases()).isEqualTo(p.getTechStack().getInfrastructure().getDatabases());
        assertThat(pd.getWebServers()).isEqualTo(p.getTechStack().getInfrastructure().getWebServers());
        assertThat(pd.getCiCdTools()).isEqualTo(p.getTechStack().getInfrastructure().getCiCdTools());
        assertThat(pd.getIacTools()).isEqualTo(p.getTechStack().getInfrastructure().getIacTools());
        assertThat(pd.getMonitoringTools()).isEqualTo(p.getTechStack().getInfrastructure().getMonitoringTools());
        assertThat(pd.getLoggingTools()).isEqualTo(p.getTechStack().getInfrastructure().getLoggingTools());

        // TechStack - Tools
        assertThat(pd.getSourceControls()).isEqualTo(p.getTechStack().getTools().getSourceControls());
        assertThat(pd.getProjectManagements()).isEqualTo(p.getTechStack().getTools().getProjectManagements());
        assertThat(pd.getCommunicationTools()).isEqualTo(p.getTechStack().getTools().getCommunicationTools());
        assertThat(pd.getDocumentationTools()).isEqualTo(p.getTechStack().getTools().getDocumentationTools());
        assertThat(pd.getApiDevelopmentTools()).isEqualTo(p.getTechStack().getTools().getApiDevelopmentTools());
        assertThat(pd.getDesignTools()).isEqualTo(p.getTechStack().getTools().getDesignTools());
        assertThat(pd.getEditors()).isEqualTo(p.getTechStack().getTools().getEditors());
        assertThat(pd.getDevelopmentEnvironments())
                .isEqualTo(p.getTechStack().getTools().getDevelopmentEnvironments());

        // Certificationインサート
        ArgumentCaptor<ResumeDto.CertificationDto> capCert = ArgumentCaptor.forClass(ResumeDto.CertificationDto.class);
        verify(mapper).insertCertification(capCert.capture());
        ResumeDto.CertificationDto certd = capCert.getValue();
        Certification cert = resume.getCertifications().get(0);
        assertThat(certd.getId()).isEqualTo(cert.getId());
        assertThat(certd.getResumeId()).isEqualTo(id);
        assertThat(certd.getName()).isEqualTo(cert.getName());
        assertThat(certd.getDate()).isEqualTo(cert.getDate());

        // Portfolioインサート
        ArgumentCaptor<ResumeDto.PortfolioDto> capPort = ArgumentCaptor.forClass(ResumeDto.PortfolioDto.class);
        verify(mapper).insertPortfolio(capPort.capture());
        ResumeDto.PortfolioDto portd = capPort.getValue();
        Portfolio port = resume.getPortfolios().get(0);
        assertThat(portd.getId()).isEqualTo(port.getId());
        assertThat(portd.getResumeId()).isEqualTo(id);
        assertThat(portd.getName()).isEqualTo(port.getName());
        assertThat(portd.getOverview()).isEqualTo(port.getOverview());
        assertThat(portd.getTechStack()).isEqualTo(port.getTechStack());
        assertThat(portd.getLink()).isEqualTo(port.getLink().getValue());

        // SocialLinkインサート
        ArgumentCaptor<ResumeDto.SocialLinkDto> capSocialLinkDto = ArgumentCaptor
                .forClass(ResumeDto.SocialLinkDto.class);
        verify(mapper).insertSocialLink(capSocialLinkDto.capture());
        ResumeDto.SocialLinkDto sld = capSocialLinkDto.getValue();
        SocialLink sl = resume.getSocialLinks().get(0);
        assertThat(sld.getId()).isEqualTo(sl.getId());
        assertThat(sld.getResumeId()).isEqualTo(id);
        assertThat(sld.getName()).isEqualTo(sl.getName());
        assertThat(sld.getLink()).isEqualTo(sl.getLink().getValue());

        // SelfPromotionインサート
        ArgumentCaptor<ResumeDto.SelfPromotionDto> capSp = ArgumentCaptor.forClass(ResumeDto.SelfPromotionDto.class);
        verify(mapper).insertSelfPromotion(capSp.capture());
        ResumeDto.SelfPromotionDto spd = capSp.getValue();
        SelfPromotion sp = resume.getSelfPromotions().get(0);
        assertThat(spd.getId()).isEqualTo(sp.getId());
        assertThat(spd.getResumeId()).isEqualTo(id);
        assertThat(spd.getTitle()).isEqualTo(sp.getTitle());
        assertThat(spd.getContent()).isEqualTo(sp.getContent());
    }

    @Test
    @DisplayName("delete_子テーブルと親テーブルの削除が正しく実行される")
    void test6() {
        repository.delete(RESUME_ID);
        verify(mapper).deleteCareersByResumeId(RESUME_ID);
        verify(mapper).deleteProjectsByResumeId(RESUME_ID);
        verify(mapper).deleteCertificationsByResumeId(RESUME_ID);
        verify(mapper).deletePortfoliosByResumeId(RESUME_ID);
        verify(mapper).deleteSocialLinksByResumeId(RESUME_ID);
        verify(mapper).deleteSelfPromotionsByResumeId(RESUME_ID);
        verify(mapper).delete(RESUME_ID);
    }
}

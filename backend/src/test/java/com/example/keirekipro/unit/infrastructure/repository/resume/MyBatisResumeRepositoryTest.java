package com.example.keirekipro.unit.infrastructure.repository.resume;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.example.keirekipro.domain.model.resume.Career;
import com.example.keirekipro.domain.model.resume.Certification;
import com.example.keirekipro.domain.model.resume.FullName;
import com.example.keirekipro.domain.model.resume.Link;
import com.example.keirekipro.domain.model.resume.Period;
import com.example.keirekipro.domain.model.resume.Portfolio;
import com.example.keirekipro.domain.model.resume.Project;
import com.example.keirekipro.domain.model.resume.Resume;
import com.example.keirekipro.domain.model.resume.ResumeName;
import com.example.keirekipro.domain.model.resume.SelfPromotion;
import com.example.keirekipro.domain.model.resume.SocialLink;
import com.example.keirekipro.domain.model.resume.TechStack;
import com.example.keirekipro.infrastructure.repository.resume.MyBatisResumeRepository;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.CareerDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.CertificationDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.PortfolioDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.ProjectDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.SelfPromotionDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeDto.SocialLinkDto;
import com.example.keirekipro.infrastructure.repository.resume.ResumeMapper;
import com.example.keirekipro.shared.Notification;

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
    private static final UUID CAREER_ID = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static final UUID PROJECT_ID = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");
    private static final UUID CERT_ID = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
    private static final UUID PORTFOLIO_ID = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
    private static final UUID SOCIALLINK_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");
    private static final UUID SELF_ID = UUID.fromString("22222222-2222-2222-2222-222222222222");

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
        ResumeDto dto = buildDto();
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
        assertThat(r.getOrderNo()).isEqualTo(dto.getOrderNo());
        assertThat(r.getUserId()).isEqualTo(dto.getUserId());
        assertThat(r.getName().getValue()).isEqualTo(dto.getName());
        assertThat(r.getDate()).isEqualTo(dto.getDate());
        assertThat(r.getFullName().getLastName()).isEqualTo(dto.getLastName());
        assertThat(r.getFullName().getFirstName()).isEqualTo(dto.getFirstName());
        assertThat(r.isAutoSaveEnabled()).isEqualTo(dto.getAutoSaveEnabled());
        assertThat(r.getCreatedAt()).isEqualTo(dto.getCreatedAt());
        assertThat(r.getUpdatedAt()).isEqualTo(dto.getUpdatedAt());

        // Careerの検証
        assertThat(r.getCareers()).hasSize(1);
        Career c = r.getCareers().get(0);
        CareerDto cd = dto.getCareers().get(0);
        assertThat(c.getId()).isEqualTo(cd.getId());
        assertThat(c.getOrderNo()).isEqualTo(cd.getOrderNo());
        assertThat(c.getCompanyName()).isEqualTo(cd.getCompanyName());
        assertThat(c.getPeriod().getStartDate()).isEqualTo(cd.getStartDate());
        assertThat(c.getPeriod().getEndDate()).isEqualTo(cd.getEndDate());
        assertThat(c.getPeriod().isActive()).isEqualTo(cd.getIsActive());

        // Projectの検証
        assertThat(r.getProjects()).hasSize(1);
        Project p = r.getProjects().get(0);
        ProjectDto pd = dto.getProjects().get(0);
        assertThat(p.getId()).isEqualTo(pd.getId());
        assertThat(p.getOrderNo()).isEqualTo(pd.getOrderNo());
        assertThat(p.getCompanyName()).isEqualTo(pd.getCompanyName());
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
        assertThat(p.getTechStack().getLanguages()).isEqualTo(pd.getLanguages());
        assertThat(p.getTechStack().getDependencies().getFrameworks()).isEqualTo(pd.getFrameworks());
        assertThat(p.getTechStack().getDependencies().getLibraries()).isEqualTo(pd.getLibraries());
        assertThat(p.getTechStack().getDependencies().getTestingTools()).isEqualTo(pd.getTestingTools());
        assertThat(p.getTechStack().getDependencies().getOrmTools()).isEqualTo(pd.getOrmTools());
        assertThat(p.getTechStack().getDependencies().getPackageManagers()).isEqualTo(pd.getPackageManagers());
        assertThat(p.getTechStack().getInfrastructure().getClouds()).isEqualTo(pd.getClouds());
        assertThat(p.getTechStack().getInfrastructure().getContainers()).isEqualTo(pd.getContainers());
        assertThat(p.getTechStack().getInfrastructure().getDatabases()).isEqualTo(pd.getDatabases());
        assertThat(p.getTechStack().getInfrastructure().getWebServers()).isEqualTo(pd.getWebServers());
        assertThat(p.getTechStack().getInfrastructure().getCiCdTools()).isEqualTo(pd.getCiCdTools());
        assertThat(p.getTechStack().getInfrastructure().getIacTools()).isEqualTo(pd.getIacTools());
        assertThat(p.getTechStack().getInfrastructure().getMonitoringTools()).isEqualTo(pd.getMonitoringTools());
        assertThat(p.getTechStack().getInfrastructure().getLoggingTools()).isEqualTo(pd.getLoggingTools());
        assertThat(p.getTechStack().getTools().getSourceControls()).isEqualTo(pd.getSourceControls());
        assertThat(p.getTechStack().getTools().getProjectManagements()).isEqualTo(pd.getProjectManagements());
        assertThat(p.getTechStack().getTools().getCommunicationTools()).isEqualTo(pd.getCommunicationTools());
        assertThat(p.getTechStack().getTools().getDocumentationTools()).isEqualTo(pd.getDocumentationTools());
        assertThat(p.getTechStack().getTools().getApiDevelopmentTools()).isEqualTo(pd.getApiDevelopmentTools());
        assertThat(p.getTechStack().getTools().getDesignTools()).isEqualTo(pd.getDesignTools());

        // Certificationの検証
        assertThat(r.getCertifications()).hasSize(1);
        Certification certEnt = r.getCertifications().get(0);
        CertificationDto certDto = dto.getCertifications().get(0);
        assertThat(certEnt.getId()).isEqualTo(certDto.getId());
        assertThat(certEnt.getOrderNo()).isEqualTo(certDto.getOrderNo());
        assertThat(certEnt.getName()).isEqualTo(certDto.getName());
        assertThat(certEnt.getDate()).isEqualTo(certDto.getDate());

        // Portfolioの検証
        assertThat(r.getPortfolios()).hasSize(1);
        Portfolio portEnt = r.getPortfolios().get(0);
        PortfolioDto portDto = dto.getPortfolios().get(0);
        assertThat(portEnt.getId()).isEqualTo(portDto.getId());
        assertThat(portEnt.getOrderNo()).isEqualTo(portDto.getOrderNo());
        assertThat(portEnt.getName()).isEqualTo(portDto.getName());
        assertThat(portEnt.getOverview()).isEqualTo(portDto.getOverview());
        assertThat(portEnt.getTechStack()).isEqualTo(portDto.getTechStack());
        assertThat(portEnt.getLink().getValue()).isEqualTo(portDto.getLink());

        // SocialLinkの検証
        assertThat(r.getSocialLinks()).hasSize(1);
        SocialLink slEnt = r.getSocialLinks().get(0);
        SocialLinkDto slDto = dto.getSocialLinks().get(0);
        assertThat(slEnt.getId()).isEqualTo(slDto.getId());
        assertThat(slEnt.getOrderNo()).isEqualTo(slDto.getOrderNo());
        assertThat(slEnt.getName()).isEqualTo(slDto.getName());
        assertThat(slEnt.getLink().getValue()).isEqualTo(slDto.getLink());

        // SelfPromotionの検証
        assertThat(r.getSelfPromotions()).hasSize(1);
        SelfPromotion spEnt = r.getSelfPromotions().get(0);
        SelfPromotionDto spDto = dto.getSelfPromotions().get(0);
        assertThat(spEnt.getId()).isEqualTo(spDto.getId());
        assertThat(spEnt.getOrderNo()).isEqualTo(spDto.getOrderNo());
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
        ResumeDto dto = buildDto();
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
        assertThat(r.getOrderNo()).isEqualTo(dto.getOrderNo());
        assertThat(r.getUserId()).isEqualTo(dto.getUserId());
        assertThat(r.getName().getValue()).isEqualTo(dto.getName());
        assertThat(r.getDate()).isEqualTo(dto.getDate());
        assertThat(r.getFullName().getLastName()).isEqualTo(dto.getLastName());
        assertThat(r.getFullName().getFirstName()).isEqualTo(dto.getFirstName());
        assertThat(r.isAutoSaveEnabled()).isEqualTo(dto.getAutoSaveEnabled());
        assertThat(r.getCreatedAt()).isEqualTo(dto.getCreatedAt());
        assertThat(r.getUpdatedAt()).isEqualTo(dto.getUpdatedAt());

        // Careerの検証
        assertThat(r.getCareers()).hasSize(dto.getCareers().size());
        ResumeDto.CareerDto cd = dto.getCareers().get(0);
        Career c = r.getCareers().get(0);
        assertThat(c.getId()).isEqualTo(cd.getId());
        assertThat(c.getOrderNo()).isEqualTo(cd.getOrderNo());
        assertThat(c.getCompanyName()).isEqualTo(cd.getCompanyName());
        assertThat(c.getPeriod().getStartDate()).isEqualTo(cd.getStartDate());
        assertThat(c.getPeriod().getEndDate()).isEqualTo(cd.getEndDate());
        assertThat(c.getPeriod().isActive()).isEqualTo(cd.getIsActive());

        // Projectの検証
        assertThat(r.getProjects()).hasSize(dto.getProjects().size());
        ResumeDto.ProjectDto pd = dto.getProjects().get(0);
        Project p = r.getProjects().get(0);
        assertThat(p.getId()).isEqualTo(pd.getId());
        assertThat(p.getOrderNo()).isEqualTo(pd.getOrderNo());
        assertThat(p.getCompanyName()).isEqualTo(pd.getCompanyName());
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
        // TechStack
        assertThat(p.getTechStack().getLanguages()).isEqualTo(pd.getLanguages());
        assertThat(p.getTechStack().getDependencies().getFrameworks()).isEqualTo(pd.getFrameworks());
        assertThat(p.getTechStack().getDependencies().getLibraries()).isEqualTo(pd.getLibraries());
        assertThat(p.getTechStack().getDependencies().getTestingTools()).isEqualTo(pd.getTestingTools());
        assertThat(p.getTechStack().getDependencies().getOrmTools()).isEqualTo(pd.getOrmTools());
        assertThat(p.getTechStack().getDependencies().getPackageManagers()).isEqualTo(pd.getPackageManagers());
        assertThat(p.getTechStack().getInfrastructure().getClouds()).isEqualTo(pd.getClouds());
        assertThat(p.getTechStack().getInfrastructure().getContainers()).isEqualTo(pd.getContainers());
        assertThat(p.getTechStack().getInfrastructure().getDatabases()).isEqualTo(pd.getDatabases());
        assertThat(p.getTechStack().getInfrastructure().getWebServers()).isEqualTo(pd.getWebServers());
        assertThat(p.getTechStack().getInfrastructure().getCiCdTools()).isEqualTo(pd.getCiCdTools());
        assertThat(p.getTechStack().getInfrastructure().getIacTools()).isEqualTo(pd.getIacTools());
        assertThat(p.getTechStack().getInfrastructure().getMonitoringTools()).isEqualTo(pd.getMonitoringTools());
        assertThat(p.getTechStack().getInfrastructure().getLoggingTools()).isEqualTo(pd.getLoggingTools());
        assertThat(p.getTechStack().getTools().getSourceControls()).isEqualTo(pd.getSourceControls());
        assertThat(p.getTechStack().getTools().getProjectManagements()).isEqualTo(pd.getProjectManagements());
        assertThat(p.getTechStack().getTools().getCommunicationTools()).isEqualTo(pd.getCommunicationTools());
        assertThat(p.getTechStack().getTools().getDocumentationTools()).isEqualTo(pd.getDocumentationTools());
        assertThat(p.getTechStack().getTools().getApiDevelopmentTools()).isEqualTo(pd.getApiDevelopmentTools());
        assertThat(p.getTechStack().getTools().getDesignTools()).isEqualTo(pd.getDesignTools());

        // Certificationの検証
        assertThat(r.getCertifications()).hasSize(dto.getCertifications().size());
        ResumeDto.CertificationDto certd = dto.getCertifications().get(0);
        Certification cert = r.getCertifications().get(0);
        assertThat(cert.getId()).isEqualTo(certd.getId());
        assertThat(cert.getOrderNo()).isEqualTo(certd.getOrderNo());
        assertThat(cert.getName()).isEqualTo(certd.getName());
        assertThat(cert.getDate()).isEqualTo(certd.getDate());

        // Portfolioの検証
        assertThat(r.getPortfolios()).hasSize(dto.getPortfolios().size());
        ResumeDto.PortfolioDto portd = dto.getPortfolios().get(0);
        Portfolio port = r.getPortfolios().get(0);
        assertThat(port.getId()).isEqualTo(portd.getId());
        assertThat(port.getOrderNo()).isEqualTo(portd.getOrderNo());
        assertThat(port.getName()).isEqualTo(portd.getName());
        assertThat(port.getOverview()).isEqualTo(portd.getOverview());
        assertThat(port.getTechStack()).isEqualTo(portd.getTechStack());
        assertThat(port.getLink().getValue()).isEqualTo(portd.getLink());

        // SocialLinkの検証
        assertThat(r.getSocialLinks()).hasSize(dto.getSocialLinks().size());
        ResumeDto.SocialLinkDto sld = dto.getSocialLinks().get(0);
        SocialLink sl = r.getSocialLinks().get(0);
        assertThat(sl.getId()).isEqualTo(sld.getId());
        assertThat(sl.getOrderNo()).isEqualTo(sld.getOrderNo());
        assertThat(sl.getName()).isEqualTo(sld.getName());
        assertThat(sl.getLink().getValue()).isEqualTo(sld.getLink());

        // SelfPromotionの検証
        assertThat(r.getSelfPromotions()).hasSize(dto.getSelfPromotions().size());
        ResumeDto.SelfPromotionDto spd = dto.getSelfPromotions().get(0);
        SelfPromotion sp = r.getSelfPromotions().get(0);
        assertThat(sp.getId()).isEqualTo(spd.getId());
        assertThat(sp.getOrderNo()).isEqualTo(spd.getOrderNo());
        assertThat(sp.getTitle()).isEqualTo(spd.getTitle());
        assertThat(sp.getContent()).isEqualTo(spd.getContent());
    }

    @Test
    @DisplayName("save_新規作成または更新時にupsertと子テーブルの削除・挿入が実行される")
    void test5() {
        // 準備
        Resume resume = buildEntity();
        UUID id = resume.getId();

        // 実行
        repository.save(resume);

        // 親テーブルupsert
        ArgumentCaptor<ResumeDto> dtoCap = ArgumentCaptor.forClass(ResumeDto.class);
        verify(mapper).upsert(dtoCap.capture());
        ResumeDto dto = dtoCap.getValue();
        assertThat(dto.getId()).isEqualTo(resume.getId());
        assertThat(dto.getOrderNo()).isEqualTo(resume.getOrderNo());
        assertThat(dto.getUserId()).isEqualTo(resume.getUserId());
        assertThat(dto.getName()).isEqualTo(resume.getName().getValue());
        assertThat(dto.getDate()).isEqualTo(resume.getDate());
        assertThat(dto.getLastName()).isEqualTo(resume.getFullName().getLastName());
        assertThat(dto.getFirstName()).isEqualTo(resume.getFullName().getFirstName());
        assertThat(dto.getAutoSaveEnabled()).isEqualTo(resume.isAutoSaveEnabled());
        assertThat(dto.getCreatedAt()).isEqualTo(resume.getCreatedAt());
        assertThat(dto.getUpdatedAt()).isEqualTo(resume.getUpdatedAt());

        // 子テーブル全削除
        verify(mapper).deleteCareersByResumeId(id);
        verify(mapper).deleteProjectsByResumeId(id);
        verify(mapper).deleteCertificationsByResumeId(id);
        verify(mapper).deletePortfoliosByResumeId(id);
        verify(mapper).deleteSocialLinksByResumeId(id);
        verify(mapper).deleteSelfPromotionsByResumeId(id);

        // 子テーブル挿入
        // Career
        ArgumentCaptor<ResumeDto.CareerDto> capC = ArgumentCaptor.forClass(ResumeDto.CareerDto.class);
        verify(mapper).insertCareer(capC.capture());
        ResumeDto.CareerDto cd = capC.getValue();
        Career c = resume.getCareers().get(0);
        assertThat(cd.getId()).isEqualTo(c.getId());
        assertThat(cd.getResumeId()).isEqualTo(id);
        assertThat(cd.getCompanyName()).isEqualTo(c.getCompanyName());
        assertThat(cd.getStartDate()).isEqualTo(c.getPeriod().getStartDate());
        assertThat(cd.getEndDate()).isEqualTo(c.getPeriod().getEndDate());
        assertThat(cd.getIsActive()).isEqualTo(c.getPeriod().isActive());
        assertThat(cd.getOrderNo()).isEqualTo(c.getOrderNo());

        // Project
        ArgumentCaptor<ResumeDto.ProjectDto> capP = ArgumentCaptor.forClass(ResumeDto.ProjectDto.class);
        verify(mapper).insertProject(capP.capture());
        ResumeDto.ProjectDto pd = capP.getValue();
        Project p = resume.getProjects().get(0);
        assertThat(pd.getId()).isEqualTo(p.getId());
        assertThat(pd.getResumeId()).isEqualTo(id);
        assertThat(pd.getCompanyName()).isEqualTo(p.getCompanyName());
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
        assertThat(pd.getLanguages()).isEqualTo(p.getTechStack().getLanguages());
        assertThat(pd.getFrameworks()).isEqualTo(p.getTechStack().getDependencies().getFrameworks());
        assertThat(pd.getLibraries()).isEqualTo(p.getTechStack().getDependencies().getLibraries());
        assertThat(pd.getTestingTools()).isEqualTo(p.getTechStack().getDependencies().getTestingTools());
        assertThat(pd.getOrmTools()).isEqualTo(p.getTechStack().getDependencies().getOrmTools());
        assertThat(pd.getPackageManagers()).isEqualTo(p.getTechStack().getDependencies().getPackageManagers());
        assertThat(pd.getClouds()).isEqualTo(p.getTechStack().getInfrastructure().getClouds());
        assertThat(pd.getContainers()).isEqualTo(p.getTechStack().getInfrastructure().getContainers());
        assertThat(pd.getDatabases()).isEqualTo(p.getTechStack().getInfrastructure().getDatabases());
        assertThat(pd.getWebServers()).isEqualTo(p.getTechStack().getInfrastructure().getWebServers());
        assertThat(pd.getCiCdTools()).isEqualTo(p.getTechStack().getInfrastructure().getCiCdTools());
        assertThat(pd.getIacTools()).isEqualTo(p.getTechStack().getInfrastructure().getIacTools());
        assertThat(pd.getMonitoringTools()).isEqualTo(p.getTechStack().getInfrastructure().getMonitoringTools());
        assertThat(pd.getLoggingTools()).isEqualTo(p.getTechStack().getInfrastructure().getLoggingTools());
        assertThat(pd.getSourceControls()).isEqualTo(p.getTechStack().getTools().getSourceControls());
        assertThat(pd.getProjectManagements()).isEqualTo(p.getTechStack().getTools().getProjectManagements());
        assertThat(pd.getCommunicationTools()).isEqualTo(p.getTechStack().getTools().getCommunicationTools());
        assertThat(pd.getDocumentationTools()).isEqualTo(p.getTechStack().getTools().getDocumentationTools());
        assertThat(pd.getApiDevelopmentTools()).isEqualTo(p.getTechStack().getTools().getApiDevelopmentTools());
        assertThat(pd.getDesignTools()).isEqualTo(p.getTechStack().getTools().getDesignTools());

        // Certification
        ArgumentCaptor<ResumeDto.CertificationDto> capCert = ArgumentCaptor.forClass(ResumeDto.CertificationDto.class);
        verify(mapper).insertCertification(capCert.capture());
        ResumeDto.CertificationDto certd = capCert.getValue();
        Certification cert = resume.getCertifications().get(0);
        assertThat(certd.getId()).isEqualTo(cert.getId());
        assertThat(certd.getResumeId()).isEqualTo(id);
        assertThat(certd.getName()).isEqualTo(cert.getName());
        assertThat(certd.getDate()).isEqualTo(cert.getDate());
        assertThat(certd.getOrderNo()).isEqualTo(cert.getOrderNo());

        // Portfolio
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
        assertThat(portd.getOrderNo()).isEqualTo(port.getOrderNo());

        // SocialLink
        ArgumentCaptor<ResumeDto.SocialLinkDto> capSL = ArgumentCaptor.forClass(ResumeDto.SocialLinkDto.class);
        verify(mapper).insertSocialLink(capSL.capture());
        ResumeDto.SocialLinkDto sld = capSL.getValue();
        SocialLink sl = resume.getSocialLinks().get(0);
        assertThat(sld.getId()).isEqualTo(sl.getId());
        assertThat(sld.getResumeId()).isEqualTo(id);
        assertThat(sld.getName()).isEqualTo(sl.getName());
        assertThat(sld.getLink()).isEqualTo(sl.getLink().getValue());
        assertThat(sld.getOrderNo()).isEqualTo(sl.getOrderNo());

        // SelfPromotion
        ArgumentCaptor<ResumeDto.SelfPromotionDto> capSP = ArgumentCaptor.forClass(ResumeDto.SelfPromotionDto.class);
        verify(mapper).insertSelfPromotion(capSP.capture());
        ResumeDto.SelfPromotionDto spd = capSP.getValue();
        SelfPromotion sp = resume.getSelfPromotions().get(0);
        assertThat(spd.getId()).isEqualTo(sp.getId());
        assertThat(spd.getResumeId()).isEqualTo(id);
        assertThat(spd.getTitle()).isEqualTo(sp.getTitle());
        assertThat(spd.getContent()).isEqualTo(sp.getContent());
        assertThat(spd.getOrderNo()).isEqualTo(sp.getOrderNo());
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

    private ResumeDto buildDto() {
        ResumeDto dto = new ResumeDto();
        dto.setId(RESUME_ID);
        dto.setUserId(USER_ID);
        dto.setName("Test Resume");
        dto.setDate(LocalDate.of(2025, 1, 1));
        dto.setLastName("Last");
        dto.setFirstName("First");
        dto.setAutoSaveEnabled(true);
        dto.setCreatedAt(LocalDateTime.of(2025, 1, 2, 3, 4));
        dto.setUpdatedAt(LocalDateTime.of(2025, 1, 3, 4, 5));
        dto.setOrderNo(7);

        // Career
        CareerDto career = new CareerDto();
        career.setId(CAREER_ID);
        career.setResumeId(RESUME_ID);
        career.setCompanyName("CompCo");
        career.setStartDate(YearMonth.of(2024, 1));
        career.setEndDate(YearMonth.of(2024, 12));
        career.setIsActive(false);
        career.setOrderNo(1);
        dto.setCareers(List.of(career));

        // Project
        ProjectDto proj = new ProjectDto();
        proj.setId(PROJECT_ID);
        proj.setResumeId(RESUME_ID);
        proj.setCompanyName("ProjCo");
        proj.setStartDate(YearMonth.of(2023, 1));
        proj.setEndDate(YearMonth.of(2023, 12));
        proj.setIsActive(false);
        proj.setName("ProjName");
        proj.setOverview("Overview");
        proj.setTeamComp("TeamX");
        proj.setRole("RoleY");
        proj.setAchievement("AchZ");
        proj.setOrderNo(2);
        proj.setRequirements(true);
        proj.setBasicDesign(false);
        proj.setDetailedDesign(true);
        proj.setImplementation(false);
        proj.setIntegrationTest(true);
        proj.setSystemTest(false);
        proj.setMaintenance(true);
        List<String> langs = List.of("Java", "SQL");
        proj.setLanguages(langs);
        proj.setFrameworks(List.of("Spring"));
        proj.setLibraries(List.of("Lib1"));
        proj.setTestingTools(List.of("Test1"));
        proj.setOrmTools(List.of("ORM1"));
        proj.setPackageManagers(List.of("Maven"));
        proj.setClouds(List.of("AWS"));
        proj.setContainers(List.of("Docker"));
        proj.setDatabases(List.of("Postgres"));
        proj.setWebServers(List.of("Tomcat"));
        proj.setCiCdTools(List.of("Jenkins"));
        proj.setIacTools(List.of("Terraform"));
        proj.setMonitoringTools(List.of("Prometheus"));
        proj.setLoggingTools(List.of("ELK"));
        proj.setSourceControls(List.of("Git"));
        proj.setProjectManagements(List.of("Jira"));
        proj.setCommunicationTools(List.of("Slack"));
        proj.setDocumentationTools(List.of("Confluence"));
        proj.setApiDevelopmentTools(List.of("Postman"));
        proj.setDesignTools(List.of("Figma"));
        dto.setProjects(List.of(proj));

        // Certification
        CertificationDto cert = new CertificationDto();
        cert.setId(CERT_ID);
        cert.setResumeId(RESUME_ID);
        cert.setName("CertX");
        cert.setDate(YearMonth.of(2022, 6));
        cert.setOrderNo(3);
        dto.setCertifications(List.of(cert));

        // Portfolio
        PortfolioDto port = new PortfolioDto();
        port.setId(PORTFOLIO_ID);
        port.setResumeId(RESUME_ID);
        port.setName("PortX");
        port.setOverview("PortOverview");
        port.setTechStack("TechStackX");
        port.setLink("http://example.com");
        port.setOrderNo(4);
        dto.setPortfolios(List.of(port));

        // SocialLink
        SocialLinkDto sl = new SocialLinkDto();
        sl.setId(SOCIALLINK_ID);
        sl.setResumeId(RESUME_ID);
        sl.setName("LinkedIn");
        sl.setLink("http://linkedin.com");
        sl.setOrderNo(5);
        dto.setSocialLinks(List.of(sl));

        // SelfPromotion
        SelfPromotionDto sp = new SelfPromotionDto();
        sp.setId(SELF_ID);
        sp.setResumeId(RESUME_ID);
        sp.setTitle("PromoTitle");
        sp.setContent("PromoContent");
        sp.setOrderNo(6);
        dto.setSelfPromotions(List.of(sp));

        return dto;
    }

    private Resume buildEntity() {
        Notification notification = new Notification();

        // Career
        Career career = Career.reconstruct(
                CAREER_ID,
                1,
                "CompCo",
                Period.create(notification, YearMonth.of(2024, 1), YearMonth.of(2024, 12), false));

        // Project
        var process = Project.Process.create(true, false, true, false, true, false, true);
        TechStack tech = TechStack.create(
                List.of("Java", "SQL"),
                TechStack.Dependencies.create(
                        List.of("Spring"),
                        List.of("Lib1"),
                        List.of("Test1"),
                        List.of("ORM1"),
                        List.of("Maven")),
                TechStack.Infrastructure.create(
                        List.of("AWS"),
                        List.of("Docker"),
                        List.of("Postgres"),
                        List.of("Tomcat"),
                        List.of("Jenkins"),
                        List.of("Terraform"),
                        List.of("Prometheus"),
                        List.of("ELK")),
                TechStack.Tools.create(
                        List.of("Git"),
                        List.of("Jira"),
                        List.of("Slack"),
                        List.of("Confluence"),
                        List.of("Postman"),
                        List.of("Figma")));
        Project project = Project.reconstruct(
                PROJECT_ID,
                2,
                "ProjCo",
                Period.create(notification, YearMonth.of(2023, 1), YearMonth.of(2023, 12), false),
                "ProjName",
                "Overview",
                "TeamX",
                "RoleY",
                "AchZ",
                process,
                tech);

        // Certification
        Certification certification = Certification.reconstruct(
                CERT_ID,
                3,
                "CertX",
                YearMonth.of(2022, 6));

        // Portfolio
        Portfolio portfolio = Portfolio.reconstruct(
                PORTFOLIO_ID,
                4,
                "PortX",
                "PortOverview",
                "TechStackX",
                Link.create(notification, "http://example.com"));

        // SocialLink
        SocialLink socialLink = SocialLink.reconstruct(
                SOCIALLINK_ID,
                5,
                "LinkedIn",
                Link.create(notification, "http://linkedin.com"));

        // SelfPromotion
        SelfPromotion self = SelfPromotion.reconstruct(
                SELF_ID,
                6,
                "PromoTitle",
                "PromoContent");

        return Resume.reconstruct(
                RESUME_ID,
                7,
                USER_ID,
                ResumeName.create(notification, "Test Resume"),
                LocalDate.of(2025, 1, 1),
                FullName.create(notification, "Last", "First"),
                true,
                LocalDateTime.of(2025, 1, 2, 3, 4),
                LocalDateTime.of(2025, 1, 3, 4, 5),
                List.of(career),
                List.of(project),
                List.of(certification),
                List.of(portfolio),
                List.of(socialLink),
                List.of(self));
    }
}

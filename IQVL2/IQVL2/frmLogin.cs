using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using System.Configuration;
using System.Data.SqlClient;
using System.IO;

namespace IQVL2
{
    public partial class frmLogin : Form
    {
        string facility;
        string username;
        int userid;

        public frmLogin()
        {
            InitializeComponent();
        }

        private void btnExit_Click(object sender, EventArgs e)
        {
            this.Close();
        }

        private void btnLogin_Click(object sender, EventArgs e)
        {
            if (txtUsername.Text.Length == 0)
            {
                MessageBox.Show("Please enter your login details", "Login failed", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            if (LoginToIQcare())
            {
                txtPass.Text = "";
                txtUsername.Text = "";
                this.Hide();
                frmMain main = new frmMain(username, facility, userid);
                main.ShowDialog();
                this.Show();
            }
            else
            {
                MessageBox.Show("Invalid Username or password. Please try again", "Login failed", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private bool LoginToIQcare()
        {
            string sPassword = GlobalFunctions.Encrypt(txtPass.Text);
            string sSQL = @"SELECT top 1 a.userID, a.UserName, a.Password, a.UserFirstName, a.UserLastName, c.GroupName
                            FROM mst_user a
                            INNER JOIN dbo.lnk_UserGroup b ON a.UserID = b.UserID
                            INNER JOIN dbo.mst_Groups c ON b.GroupID = c.GroupID
                            WHERE a.DeleteFlag = 0 AND a.UserName = '" + txtUsername.Text + "' AND Password = '" + sPassword + "'";

            DataSet ds = GlobalFunctions.ExecuteQuery(sSQL);

            if (ds.Tables[0].Rows.Count == 0)
            {
                return false;
            }
            else
            {
                username = ds.Tables[0].Rows[0]["UserFirstName"].ToString() + " " + ds.Tables[0].Rows[0]["UserLastName"].ToString();
                facility = txtFacilityName.Text;
                userid = Convert.ToInt32(ds.Tables[0].Rows[0]["userID"].ToString());
                return true;
            }
        }

        private void btnSaveSettings_Click(object sender, EventArgs e)
        {
            this.Cursor = Cursors.WaitCursor;

            if (txtServerName.Text.Trim() == "")
            {
                MessageBox.Show("Please enter all the details before saving");
                return;
            }

            try
            {
                string scon = "Data Source=" + txtServerName.Text.Trim() + ";Initial Catalog="+txtDatabase.Text.Trim()+";User ID="+txtLoginName.Text+";Password="+txtPassword.Text;

                if (ValidateSettings(scon))
                {
                    // Get the application configuration file.
                    System.Configuration.Configuration config = ConfigurationManager.OpenExeConfiguration(ConfigurationUserLevel.None);

                    // Get the connection strings section.
                    ConnectionStringsSection csSection = config.ConnectionStrings;

                    // Update connection string.
                    csSection.ConnectionStrings["IQCareConnectionString"].ConnectionString = scon;

                    // Save the configuration file.
                    config.Save();
                    MessageBox.Show("Settings saved successfully. Please restart the application");
                    this.Close();
                }
                else
                {
                    MessageBox.Show("Attempt to connect to the specified server failed. Please correct the details and try again");
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("The following error occured: " + ex.Message);
            }

            this.Cursor = Cursors.Default;
        }

        public static bool ValidateSettings(string sConString)
        {
            try
            {
                SqlConnection con = new SqlConnection(sConString + "; Connection Timeout=10");
                con.Open();
                con.Close();

                return true;
            }
            catch (Exception ex)
            {
                return false;
            }
        }

        private void ExecuteUpgradeScripts()
        {
            string scriptDirectory = Environment.CurrentDirectory + "\\scripts\\";
            string sqlConnectionString = ConfigurationManager.ConnectionStrings["IQCareConnectionString"].ConnectionString;

            DirectoryInfo di = new DirectoryInfo(scriptDirectory);
            FileInfo[] rgFiles = di.GetFiles("*.sql");

            foreach (FileInfo fi in rgFiles)
            {
                FileInfo fileInfo = new FileInfo(fi.FullName);
                string script = fileInfo.OpenText().ReadToEnd();
                using (SqlConnection connection = new SqlConnection(sqlConnectionString))
                {
                    GlobalFunctions.ExecuteBatchNonQuery(script, connection);
                }
            }
        }

        private void frmLogin_Load(object sender, EventArgs e)
        {
            string sconstring = ConfigurationManager.ConnectionStrings["IQCareConnectionString"].ConnectionString;

            if (ValidateSettings(sconstring))
            {
                txtPass.Enabled = true;
                txtUsername.Enabled = true;
                btnLogin.Enabled = true;
                lblErrorMsg.Text = "";

                DataSet ds = GlobalFunctions.ExecuteQuery("select top 1 FacilityName from mst_Facility where DeleteFlag=0");
                txtFacilityName.Text = ds.Tables[0].Rows[0]["FacilityName"].ToString();

                ExecuteUpgradeScripts();
            }
            else
            {
                txtPass.Enabled = false;
                txtUsername.Enabled = false;
                btnLogin.Enabled = false;
                lblErrorMsg.Text = "Invalid settings, please correct";
            }

            txtUsername.Focus();
        }
    }
}

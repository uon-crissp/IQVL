using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using GenericParsing;
using System.Configuration;
using System.Data.SqlClient;
using Excel = Microsoft.Office.Interop.Excel;
using System.IO;

namespace IQVL2
{
    public partial class frmMain : Form
    {
        public static string sConnectionString = ConfigurationManager.ConnectionStrings["IQCareConnectionString"].ConnectionString;
        DataClasses1DataContext oDAL = new DataClasses1DataContext(sConnectionString);
        DataTable dt;
        DataTable dt_errors = new DataTable();
        List<int> errorids = new List<int>();
        List<string> errormsg = new List<string>();

        string username;
        string facility;
        int userid;

        public frmMain(string _username, string _facility, int _userid)
        {
            InitializeComponent();

            username = _username;
            facility = _facility;
            userid = _userid;
        }

        private void btnBrowseFile_Click(object sender, EventArgs e)
        {
            OpenFileDialog openFileDialog1 = new OpenFileDialog();
            openFileDialog1.Filter = "CSV File|*.csv";
            openFileDialog1.Title = "Select the VL Results file";  

            if (openFileDialog1.ShowDialog() == System.Windows.Forms.DialogResult.OK)
            {
                using (GenericParserAdapter parser = new GenericParserAdapter(openFileDialog1.FileName))
                {
                    DataSet ds = new DataSet();

                    //Load the data
                    ds = parser.GetDataSet();
                    dt =  ds.Tables[0];

                    //Format the data
                    foreach (DataColumn dc in dt.Columns)
                    {
                        dc.ColumnName = dt.Rows[0][dc].ToString();
                    }
                    dt.Rows[0].Delete();

                    //Display the data
                    dgvResults.DataSource = dt;
                }
            }
        }

        private void frmMain_Load(object sender, EventArgs e)
        {
            lblProgress.Text = "";
            dgvOrders.ClipboardCopyMode = DataGridViewClipboardCopyMode.EnableAlwaysIncludeHeaderText;

            this.Text = "IQVL 2.0 - " + facility + " (" + username + ")";
        }

        private void btnUploadResults_Click(object sender, EventArgs e)
        {
            btnBrowseFile.Enabled = false;
            btnUploadResults.Enabled = false;
            lblProgress.ForeColor = Color.Red;
            lblProgress.Text = "Uploading...";
            backgroundWorker1.RunWorkerAsync();
        }

        private void cmdExport_Click(object sender, EventArgs e)
        {
            SaveFileDialog sfd = new SaveFileDialog();
            sfd.Filter = "Excel Documents (*.xls)|*.xls";
            if (sfd.ShowDialog() == DialogResult.OK)
            {
                // Copy DataGridView results to clipboard
                copyAlltoClipboard();

                object misValue = System.Reflection.Missing.Value;
                Excel.Application xlexcel = new Excel.Application();

                xlexcel.DisplayAlerts = false; // Without this you will get two confirm overwrite prompts
                Excel.Workbook xlWorkBook = xlexcel.Workbooks.Add(misValue);
                Excel.Worksheet xlWorkSheet = (Excel.Worksheet)xlWorkBook.Worksheets.get_Item(1);

                // Format column D as text before pasting results, this was required for my data
                Excel.Range rng = xlWorkSheet.get_Range("D:D").Cells;
                rng.NumberFormat = "@";

                // Paste clipboard results to worksheet range
                Excel.Range CR = (Excel.Range)xlWorkSheet.Cells[1, 1];
                CR.Select();
                xlWorkSheet.PasteSpecial(CR, Type.Missing, Type.Missing, Type.Missing, Type.Missing, Type.Missing, true);

                // For some reason column A is always blank in the worksheet.
                // Delete blank column A and select cell A1
                Excel.Range delRng = xlWorkSheet.get_Range("A:A").Cells;
                delRng.Delete(Type.Missing);
                xlWorkSheet.get_Range("A1").Select();

                // Save the excel file under the captured location from the SaveFileDialog
                xlWorkBook.SaveAs(sfd.FileName, Excel.XlFileFormat.xlWorkbookNormal, misValue, misValue, misValue, misValue, Excel.XlSaveAsAccessMode.xlExclusive, misValue, misValue, misValue, misValue, misValue);
                xlexcel.DisplayAlerts = true;
                xlWorkBook.Close(true, misValue, misValue);
                xlexcel.Quit();

                releaseObject(xlWorkSheet);
                releaseObject(xlWorkBook);
                releaseObject(xlexcel);

                // Clear Clipboard and DataGridView selection
                Clipboard.Clear();
                dgvOrders.ClearSelection();

                // Open the newly saved excel file
                if (File.Exists(sfd.FileName))
                {
                    System.Diagnostics.Process.Start(sfd.FileName);
                }
            }
        }

        private void copyAlltoClipboard()
        {
            dgvOrders.SelectAll();
            DataObject dataObj = dgvOrders.GetClipboardContent();
            if (dataObj != null)
                Clipboard.SetDataObject(dataObj);
        }

        private void releaseObject(object obj)
        {
            try
            {
                System.Runtime.InteropServices.Marshal.ReleaseComObject(obj);
                obj = null;
            }
            catch (Exception ex)
            {
                obj = null;
                MessageBox.Show("Exception Occurred while releasing object " + ex.ToString());
            }
            finally
            {
                GC.Collect();
            }
        }

        private void backgroundWorker1_DoWork(object sender, DoWorkEventArgs e)
        {
            int i=0;
            int iTotalRecords = dt.Rows.Count;
            bool iResultsFromKNH;

            if (dt.Columns[0].Caption == "Lab ID")
            {
                iResultsFromKNH = true;
            }
            else
            {
                iResultsFromKNH = false;
            }

            foreach (DataRow row in dt.Rows)
            {
                try
                {
                    string sPatientId;
                    DateTime OrderDate;
                    DateTime ReportedDate;
                    string sResult;

                    if (iResultsFromKNH)
                    {
                        sPatientId = row["Patient CCC No"].ToString();
                        OrderDate = Convert.ToDateTime(row["Collection Date"]);
                        ReportedDate = Convert.ToDateTime(row["Date of Testing"]);
                        sResult = row["Viral Load"].ToString();
                    }
                    else
                    {
                        sPatientId = row["Patient CCC No"].ToString();
                        OrderDate = Convert.ToDateTime(row["Date Collected"]);
                        ReportedDate = Convert.ToDateTime(row["Date Tested"]);
                        sResult = row["Result"].ToString();
                    }

                    int iUserId = userid;
                    Decimal dResult = 0;

                    if (sResult.ToLower().Contains("new sample") || sResult.ToLower().Contains("invalid"))
                    {
                        //Invalid result. Do not process
                    }
                    else
                    {
                        if (sResult.ToLower().Contains("ldl"))
                        {
                            dResult = 0;
                        }
                        else
                        {
                            dResult = Convert.ToDecimal(sResult);
                        }

                        oDAL.pr_IQVL_SaveLabResult(sPatientId.Trim(), OrderDate, ReportedDate, dResult, iUserId);
                    }
                }
                catch(Exception ex)
                {
                    errorids.Add(i);
                    errormsg.Add(row["Patient CCC No"].ToString() + ": " + ex.Message);
                }

                i++;
                int progress = Convert.ToInt32((Convert.ToDecimal(i) / Convert.ToDecimal(iTotalRecords)) * 100);
                backgroundWorker1.ReportProgress(progress);
            }
        }

        private void backgroundWorker1_ProgressChanged(object sender, ProgressChangedEventArgs e)
        {
            lblProgress.Text = "Uploading... "+e.ProgressPercentage.ToString() + "%";
            txtLogs.Text = string.Join(Environment.NewLine, errormsg.ToArray());
        }

        private void backgroundWorker1_RunWorkerCompleted(object sender, RunWorkerCompletedEventArgs e)
        {
            lblProgress.ForeColor = Color.Green;
            lblProgress.Text = "Uploading completed";
            btnBrowseFile.Enabled = true;
            btnUploadResults.Enabled = true;

            if (errorids.Count == 0)
            {
                MessageBox.Show("Viral load results uploaded successfully with no errors", "SUCCESSFUL", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                //Display errors
                foreach (int i in errorids)
                {
                    dgvResults.Rows[i].DefaultCellStyle.BackColor = Color.Red;
                    dgvResults.Rows[i].Cells[0].Value = "ERROR";
                }

                MessageBox.Show("Viral load results uploaded, but with ERRORS in "+ errorids.Count.ToString()+ " records", "Error in some records", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        private void cmdGenerateList_Click(object sender, EventArgs e)
        {
            try
            {
                this.Cursor = Cursors.WaitCursor;
                DataSet ds = LoadVLOrders();
                dgvOrders.DataSource = ds.Tables[0];
                this.Cursor = Cursors.Default;
            }
            catch (Exception ex)
            {
                this.Cursor = Cursors.Default;
                MessageBox.Show(ex.Message);
            }
        }

        public DataSet LoadVLOrders()
        {
            SqlConnection con = new SqlConnection(sConnectionString);

            con.Open();

            SqlCommand command = new SqlCommand("pr_IQVL_LoadVLOrders", con);
            command.CommandType = CommandType.StoredProcedure;
            command.CommandTimeout = 0;

            command.Parameters.Add(new SqlParameter("@fromdate", dateTimePicker1.Text));
            command.Parameters.Add(new SqlParameter("@todate", dateTimePicker2.Text));

            DataSet ds = new DataSet();
            SqlDataAdapter adapter = new SqlDataAdapter();
            adapter.SelectCommand = command;
            adapter.Fill(ds);

            con.Close();
            return ds;
        }
    }
}
